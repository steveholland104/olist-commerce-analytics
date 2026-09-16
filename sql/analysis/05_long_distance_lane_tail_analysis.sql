-- Long-distance carrier-transit tail analysis by seller-to-customer lane
-- Purpose: Identify seller-state to customer-state lanes that disproportionately contribute to extreme carrier-transit failures among long-distance orders.
-- Long-distance definition: Seller-to-customer distance greater than 1,000 km.
-- Extreme-tail definition: Carrier transit at or above the 95th percentile among all valid long-distance single-seller orders.
-- Geography: Uses median latitude/longitude by ZIP prefix after excluding coordinates outside a broad plausible Brazil bounding box.
-- Grain: One row per delivered single-seller order before lane aggregation.

WITH zip_geography AS (
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
long_distance_orders AS (
    SELECT
        order_distance.order_id,
        order_distance.distance_km,
        order_distance.seller_state,
        order_distance.customer_state,
        EXTRACT(
            EPOCH FROM (
                raw.orders.order_delivered_customer_date
                - raw.orders.order_delivered_carrier_date
            )
        ) / 86400.0 AS carrier_to_customer_days
    FROM order_distance
    JOIN raw.orders
        ON order_distance.order_id = raw.orders.order_id
    WHERE order_distance.distance_km > 1000
        AND raw.orders.order_delivered_carrier_date IS NOT NULL
        AND raw.orders.order_delivered_customer_date IS NOT NULL
        AND raw.orders.order_delivered_customer_date >= raw.orders.order_delivered_carrier_date
),
tail_threshold AS (
    SELECT
        PERCENTILE_CONT(0.95)
            WITHIN GROUP (
                ORDER BY long_distance_orders.carrier_to_customer_days
            ) AS p95_carrier_to_customer_days
    FROM long_distance_orders
),
long_distance_flagged AS (
    SELECT
        long_distance_orders.order_id,
        long_distance_orders.distance_km,
        long_distance_orders.seller_state,
        long_distance_orders.customer_state,
        long_distance_orders.carrier_to_customer_days,
        tail_threshold.p95_carrier_to_customer_days,
        CASE
            WHEN long_distance_orders.carrier_to_customer_days >= tail_threshold.p95_carrier_to_customer_days
            THEN 1
            ELSE 0
        END AS extreme_tail
    FROM long_distance_orders
    CROSS JOIN tail_threshold
),
tail_totals AS (
    SELECT
        COUNT(*) AS long_distance_orders,
        SUM(long_distance_flagged.extreme_tail) AS total_extreme_tail_orders,
        AVG(long_distance_flagged.extreme_tail) AS overall_extreme_tail_rate,
        MAX(long_distance_flagged.p95_carrier_to_customer_days) AS p95_carrier_to_customer_days
    FROM long_distance_flagged
),
lane_tail_summary AS (
    SELECT
        long_distance_flagged.seller_state,
        long_distance_flagged.customer_state,
        COUNT(*) AS long_distance_orders,
        ROUND(
            AVG(long_distance_flagged.distance_km)::NUMERIC,
            2
        ) AS avg_distance_km,
        ROUND(
            AVG(long_distance_flagged.carrier_to_customer_days)::NUMERIC,
            2
        ) AS avg_carrier_to_customer_days,
        ROUND(
            PERCENTILE_CONT(0.95)
                WITHIN GROUP (
                    ORDER BY long_distance_flagged.carrier_to_customer_days
                )::NUMERIC,
            2
        ) AS lane_p95_carrier_days,
        SUM(long_distance_flagged.extreme_tail) AS extreme_tail_orders,
        ROUND(
            100.0 * AVG(long_distance_flagged.extreme_tail),
            2
        ) AS pct_lane_orders_extreme_tail
    FROM long_distance_flagged
    GROUP BY
        long_distance_flagged.seller_state,
        long_distance_flagged.customer_state
)
SELECT
    lane_tail_summary.seller_state,
    lane_tail_summary.customer_state,
    lane_tail_summary.long_distance_orders,
    lane_tail_summary.avg_distance_km,
    lane_tail_summary.avg_carrier_to_customer_days,
    lane_tail_summary.lane_p95_carrier_days,
    lane_tail_summary.extreme_tail_orders,
    lane_tail_summary.pct_lane_orders_extreme_tail,
    ROUND(
        100.0
        * lane_tail_summary.extreme_tail_orders
        / tail_totals.total_extreme_tail_orders,
        2
    ) AS pct_of_all_extreme_tail_orders,
    ROUND(
        AVG(lane_tail_summary.extreme_tail_orders::NUMERIC / lane_tail_summary.long_distance_orders)
        / tail_totals.overall_extreme_tail_rate,
        2
    ) AS extreme_tail_lift,
    ROUND(
        tail_totals.p95_carrier_to_customer_days::NUMERIC,
        2
    ) AS overall_p95_carrier_days
FROM lane_tail_summary
CROSS JOIN tail_totals
WHERE lane_tail_summary.long_distance_orders >= 50
GROUP BY
    lane_tail_summary.seller_state,
    lane_tail_summary.customer_state,
    lane_tail_summary.long_distance_orders,
    lane_tail_summary.avg_distance_km,
    lane_tail_summary.avg_carrier_to_customer_days,
    lane_tail_summary.lane_p95_carrier_days,
    lane_tail_summary.extreme_tail_orders,
    lane_tail_summary.pct_lane_orders_extreme_tail,
    tail_totals.total_extreme_tail_orders,
    tail_totals.overall_extreme_tail_rate,
    tail_totals.p95_carrier_to_customer_days
ORDER BY
    lane_tail_summary.extreme_tail_orders DESC,
    lane_tail_summary.pct_lane_orders_extreme_tail DESC;