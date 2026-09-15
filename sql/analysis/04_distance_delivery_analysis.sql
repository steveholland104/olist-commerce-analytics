-- Seller-to-customer distance and delivery experience analysis
-- Purpose: Determine whether delivery reliability and customer experience
-- deteriorate as physical distance between seller and customer increases.
-- Geography: Uses median latitude/longitude by ZIP prefix after excluding coordinates outside a broad plausible Brazil bounding box.
-- Grain: One row per delivered single-seller order with valid seller and
-- customer coordinates before distance-bucket aggregation.

WITH latest_review AS (
    SELECT
        raw.order_reviews.order_id,
        raw.order_reviews.review_score,
        raw.order_reviews.review_answer_timestamp,
        ROW_NUMBER()
            OVER (
                PARTITION BY raw.order_reviews.order_id
                ORDER BY
                    raw.order_reviews.review_answer_timestamp DESC,
                    raw.order_reviews.review_id DESC
            ) AS review_rank
    FROM raw.order_reviews
),
zip_geography AS (
    SELECT
        raw.geolocation.geolocation_zip_code_prefix,
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY raw.geolocation.geolocation_lat
            ) AS median_latitude,
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY raw.geolocation.geolocation_lng
            ) AS median_longitude
    FROM raw.geolocation
	WHERE raw.geolocation.geolocation_lat BETWEEN -35 AND 6
	    AND raw.geolocation.geolocation_lng BETWEEN -75 AND -30
    GROUP BY
        raw.geolocation.geolocation_zip_code_prefix
),
customer_geography AS (
    SELECT
        raw.customers.customer_id,
        raw.customers.customer_state,
        raw.customers.customer_zip_code_prefix,
        zip_geography.median_latitude AS customer_latitude,
        zip_geography.median_longitude AS customer_longitude
    FROM raw.customers
    LEFT JOIN zip_geography
        ON raw.customers.customer_zip_code_prefix = zip_geography.geolocation_zip_code_prefix
),
seller_geography AS (
    SELECT
        raw.sellers.seller_id,
        raw.sellers.seller_state,
        raw.sellers.seller_zip_code_prefix,
        zip_geography.median_latitude AS seller_latitude,
        zip_geography.median_longitude AS seller_longitude
    FROM raw.sellers
    LEFT JOIN zip_geography
        ON raw.sellers.seller_zip_code_prefix = zip_geography.geolocation_zip_code_prefix
),
order_seller AS (
    SELECT DISTINCT
        raw.order_items.order_id,
        raw.order_items.seller_id
    FROM raw.order_items
),
seller_count AS (
    SELECT
        order_seller.order_id,
        COUNT(*) AS seller_count
    FROM order_seller
    GROUP BY
        order_seller.order_id
),
single_seller_order AS (
    SELECT
        order_seller.order_id,
        order_seller.seller_id
    FROM order_seller
    JOIN seller_count
        ON order_seller.order_id = seller_count.order_id
    WHERE seller_count.seller_count = 1
),
order_geography AS (
    SELECT
        raw.orders.order_id,
        customer_geography.customer_state,
        customer_geography.customer_zip_code_prefix,
        customer_geography.customer_latitude,
        customer_geography.customer_longitude,
        seller_geography.seller_state,
        seller_geography.seller_zip_code_prefix,
        seller_geography.seller_latitude,
        seller_geography.seller_longitude
    FROM raw.orders
    JOIN customer_geography
        ON raw.orders.customer_id = customer_geography.customer_id
    JOIN single_seller_order
        ON raw.orders.order_id = single_seller_order.order_id
    JOIN seller_geography
        ON single_seller_order.seller_id = seller_geography.seller_id
    WHERE raw.orders.order_status = 'delivered'
        AND raw.orders.order_delivered_customer_date IS NOT NULL
),
order_distance AS (
    SELECT
        order_geography.order_id,
        order_geography.seller_state,
        order_geography.customer_state,
        order_geography.seller_zip_code_prefix,
        order_geography.customer_zip_code_prefix,
        order_geography.seller_latitude,
        order_geography.seller_longitude,
        order_geography.customer_latitude,
        order_geography.customer_longitude,
        2 * 6371 * ASIN(
            SQRT(
                POWER(
                    SIN(
                        RADIANS(
                            order_geography.customer_latitude
                            - order_geography.seller_latitude
                        ) / 2
                    ),
                    2
                )
                + COS(RADIANS(order_geography.seller_latitude))
                * COS(RADIANS(order_geography.customer_latitude))
                * POWER(
                    SIN(
                        RADIANS(
                            order_geography.customer_longitude
                            - order_geography.seller_longitude
                        ) / 2
                    ),
                    2
                )
            )
        ) AS distance_km
    FROM order_geography
    WHERE order_geography.customer_latitude IS NOT NULL
        AND order_geography.customer_longitude IS NOT NULL
        AND order_geography.seller_latitude IS NOT NULL
        AND order_geography.seller_longitude IS NOT NULL
),
distance_order_experience AS (
    SELECT
        order_distance.order_id,
        order_distance.distance_km,
        order_distance.seller_state,
        order_distance.customer_state,
        latest_review.review_score,
        latest_review.review_answer_timestamp,
        raw.orders.order_delivered_customer_date,
        raw.orders.order_estimated_delivery_date,
        CASE
            WHEN raw.orders.order_delivered_customer_date::DATE
                > raw.orders.order_estimated_delivery_date::DATE
            THEN 1
            ELSE 0
        END AS order_was_late,
        CASE
            WHEN raw.orders.order_delivered_customer_date::DATE
                - raw.orders.order_estimated_delivery_date::DATE > 10
            THEN 1
            ELSE 0
        END AS order_was_severely_late,
        CASE
            WHEN latest_review.review_answer_timestamp IS NULL
            THEN NULL
            WHEN latest_review.review_answer_timestamp
                < raw.orders.order_delivered_customer_date
            THEN 1
            ELSE 0
        END AS review_before_delivery,
        CASE
            WHEN latest_review.review_score IS NULL
            THEN NULL
            WHEN latest_review.review_score <= 2
            THEN 1
            ELSE 0
        END AS poor_review
    FROM order_distance
    JOIN raw.orders
        ON order_distance.order_id = raw.orders.order_id
    LEFT JOIN latest_review
        ON order_distance.order_id = latest_review.order_id
        AND latest_review.review_rank = 1
),
distance_bucketed AS (
    SELECT
        distance_order_experience.order_id,
        distance_order_experience.distance_km,
        distance_order_experience.review_score,
        distance_order_experience.order_was_late,
        distance_order_experience.order_was_severely_late,
        distance_order_experience.review_before_delivery,
        distance_order_experience.poor_review,
        CASE
            WHEN distance_order_experience.distance_km <= 100
            THEN 1
            WHEN distance_order_experience.distance_km <= 250
            THEN 2
            WHEN distance_order_experience.distance_km <= 500
            THEN 3
            WHEN distance_order_experience.distance_km <= 1000
            THEN 4
            WHEN distance_order_experience.distance_km <= 2000
            THEN 5
            ELSE 6
        END AS distance_bucket_order,
        CASE
            WHEN distance_order_experience.distance_km <= 100
            THEN '0 - 100 km'
            WHEN distance_order_experience.distance_km <= 250
            THEN '100 - 250 km'
            WHEN distance_order_experience.distance_km <= 500
            THEN '250 - 500 km'
            WHEN distance_order_experience.distance_km <= 1000
            THEN '500 - 1000 km'
            WHEN distance_order_experience.distance_km <= 2000
            THEN '1000 - 2000 km'
            ELSE '2000+ km'
        END AS distance_bucket
    FROM distance_order_experience
),
distance_bucket_summary AS (
    SELECT
        distance_bucketed.distance_bucket_order,
        distance_bucketed.distance_bucket,
        COUNT(*) AS delivered_orders,
        COUNT(distance_bucketed.review_score) AS reviewed_orders,
        ROUND(
            AVG(distance_bucketed.distance_km)::NUMERIC,
            2
        ) AS avg_distance_km,
        ROUND(
            AVG(distance_bucketed.review_score),
            2
        ) AS avg_review_score,
        ROUND(
            100.0 * AVG(distance_bucketed.poor_review),
            2
        ) AS pct_poor_review,
        ROUND(
            100.0 * AVG(distance_bucketed.order_was_late),
            2
        ) AS pct_late,
        ROUND(
            100.0 * AVG(distance_bucketed.order_was_severely_late),
            2
        ) AS pct_more_than_10_days_late,
        COUNT(*) FILTER (
            WHERE distance_bucketed.order_was_late = 1
                AND distance_bucketed.review_before_delivery = 1
        ) AS late_and_reviewed_before_delivery,
        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE distance_bucketed.order_was_late = 1
                    AND distance_bucketed.review_before_delivery = 1
            )
            / COUNT(*),
            2
        ) AS pct_all_orders_late_and_reviewed_before_delivery,
        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE distance_bucketed.order_was_late = 1
                    AND distance_bucketed.review_before_delivery = 1
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE distance_bucketed.order_was_late = 1
                ),
                0
            ),
            2
        ) AS pct_late_orders_reviewed_before_delivery
    FROM distance_bucketed
    GROUP BY
        distance_bucketed.distance_bucket_order,
        distance_bucketed.distance_bucket
)
SELECT
    distance_bucket_summary.distance_bucket,
    distance_bucket_summary.delivered_orders,
    distance_bucket_summary.reviewed_orders,
    distance_bucket_summary.avg_distance_km,
    distance_bucket_summary.avg_review_score,
    distance_bucket_summary.pct_poor_review,
    distance_bucket_summary.pct_late,
    distance_bucket_summary.pct_more_than_10_days_late,
    distance_bucket_summary.late_and_reviewed_before_delivery,
    distance_bucket_summary.pct_all_orders_late_and_reviewed_before_delivery,
    distance_bucket_summary.pct_late_orders_reviewed_before_delivery
FROM distance_bucket_summary
ORDER BY
    distance_bucket_summary.distance_bucket_order;