-- Long-distance seller extreme-tail concentration analysis
-- Purpose: Determine whether extreme carrier-transit failures are concentrated among a small subset of sellers or broadly distributed across the seller base.
-- Long-distance definition: Seller-to-customer distance greater than 1,000 km.
-- Extreme-tail definition: Carrier transit at or above the 95th percentile among all valid long-distance single-seller orders in the analysis period.
-- Calendar period: January 2017 through August 2018.
-- Seller concentration is evaluated using both failure share and order-volume share so that high-volume sellers are not automatically treated as high-risk.
-- Important limitation: Seller identity may proxy for product mix, geography, logistics arrangements, carrier relationships, or other un-observed factors.



WITH zip_geography AS (
    SELECT
        raw.geolocation.geolocation_zip_code_prefix,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY raw.geolocation.geolocation_lat) AS median_latitude,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY raw.geolocation.geolocation_lng) AS median_longitude
    FROM raw.geolocation
    WHERE raw.geolocation.geolocation_lat BETWEEN -35 AND 6
        AND raw.geolocation.geolocation_lng BETWEEN -75 AND -30
    GROUP BY
        raw.geolocation.geolocation_zip_code_prefix
),
customer_geography AS (
    SELECT
        raw.customers.customer_id,
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
        single_seller_order.seller_id,
        seller_geography.seller_state,
        customer_geography.customer_latitude,
        customer_geography.customer_longitude,
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
        order_geography.seller_id,
        order_geography.seller_state,
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
        order_distance.seller_id,
        order_distance.seller_state,
        order_distance.distance_km,
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
        AND raw.orders.order_purchase_timestamp >= '2017-01-01'
        AND raw.orders.order_purchase_timestamp < '2018-09-01'
        AND raw.orders.order_delivered_carrier_date IS NOT NULL
        AND raw.orders.order_delivered_customer_date IS NOT NULL
        AND raw.orders.order_delivered_customer_date >= raw.orders.order_delivered_carrier_date
),
tail_threshold AS (
    SELECT
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY long_distance_orders.carrier_to_customer_days) AS p95_carrier_to_customer_days
    FROM long_distance_orders
),
long_distance_flagged AS (
    SELECT
        long_distance_orders.order_id,
        long_distance_orders.seller_id,
        long_distance_orders.seller_state,
        long_distance_orders.distance_km,
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
        COUNT(DISTINCT long_distance_flagged.seller_id) AS long_distance_sellers,
        SUM(long_distance_flagged.extreme_tail) AS total_extreme_tail_orders,
        AVG(long_distance_flagged.extreme_tail) AS overall_extreme_tail_rate,
        MAX(long_distance_flagged.p95_carrier_to_customer_days) AS overall_p95_carrier_days
    FROM long_distance_flagged
),
seller_summary AS (
    SELECT
        long_distance_flagged.seller_id,
        long_distance_flagged.seller_state,
        COUNT(*) AS long_distance_orders,
        ROUND(AVG(long_distance_flagged.distance_km)::NUMERIC, 2) AS avg_distance_km,
        ROUND(AVG(long_distance_flagged.carrier_to_customer_days)::NUMERIC, 2) AS avg_carrier_to_customer_days,
        SUM(long_distance_flagged.extreme_tail) AS extreme_tail_orders,
        AVG(long_distance_flagged.extreme_tail) AS seller_extreme_tail_rate
    FROM long_distance_flagged
    GROUP BY
        long_distance_flagged.seller_id,
        long_distance_flagged.seller_state
),
seller_ranked AS (
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY
                seller_summary.extreme_tail_orders DESC,
                seller_summary.long_distance_orders DESC,
                seller_summary.seller_id
        ) AS seller_rank,
        seller_summary.seller_id,
        seller_summary.seller_state,
        seller_summary.long_distance_orders,
        seller_summary.avg_distance_km,
        seller_summary.avg_carrier_to_customer_days,
        seller_summary.extreme_tail_orders,
        seller_summary.seller_extreme_tail_rate,
        seller_summary.long_distance_orders * tail_totals.overall_extreme_tail_rate AS expected_extreme_tail_orders,
        seller_summary.extreme_tail_orders - seller_summary.long_distance_orders * tail_totals.overall_extreme_tail_rate AS excess_extreme_tail_orders,
        100.0 * seller_summary.long_distance_orders / tail_totals.long_distance_orders AS pct_all_long_distance_orders,
        100.0 * seller_summary.extreme_tail_orders / tail_totals.total_extreme_tail_orders AS pct_all_extreme_tail_orders,
        100.0 * SUM(seller_summary.long_distance_orders) OVER (
            ORDER BY
                seller_summary.extreme_tail_orders DESC,
                seller_summary.long_distance_orders DESC,
                seller_summary.seller_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / tail_totals.long_distance_orders AS cumulative_pct_all_long_distance_orders,
        100.0 * SUM(seller_summary.extreme_tail_orders) OVER (
            ORDER BY
                seller_summary.extreme_tail_orders DESC,
                seller_summary.long_distance_orders DESC,
                seller_summary.seller_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / tail_totals.total_extreme_tail_orders AS cumulative_pct_all_extreme_tail_orders,
        tail_totals.overall_extreme_tail_rate,
        tail_totals.overall_p95_carrier_days
    FROM seller_summary
    CROSS JOIN tail_totals
),
concentration_points(top_sellers) AS (
    VALUES
        (10),
        (25),
        (50)
),
concentration_summary AS (
    SELECT
        concentration_points.top_sellers,
        SUM(
            CASE
                WHEN seller_ranked.seller_rank <= concentration_points.top_sellers
                THEN seller_ranked.long_distance_orders
                ELSE 0
            END
        ) AS long_distance_orders,
        SUM(
            CASE
                WHEN seller_ranked.seller_rank <= concentration_points.top_sellers
                THEN seller_ranked.extreme_tail_orders
                ELSE 0
            END
        ) AS extreme_tail_orders,
        SUM(
            CASE
                WHEN seller_ranked.seller_rank <= concentration_points.top_sellers
                THEN seller_ranked.expected_extreme_tail_orders
                ELSE 0
            END
        ) AS expected_extreme_tail_orders,
        SUM(
            CASE
                WHEN seller_ranked.seller_rank <= concentration_points.top_sellers
                THEN seller_ranked.excess_extreme_tail_orders
                ELSE 0
            END
        ) AS excess_extreme_tail_orders,
        MAX(seller_ranked.overall_extreme_tail_rate) AS overall_extreme_tail_rate,
        MAX(seller_ranked.overall_p95_carrier_days) AS overall_p95_carrier_days,
        MAX(
            CASE
                WHEN seller_ranked.seller_rank = concentration_points.top_sellers
                THEN seller_ranked.cumulative_pct_all_long_distance_orders
            END
        ) AS cumulative_pct_all_long_distance_orders,
        MAX(
            CASE
                WHEN seller_ranked.seller_rank = concentration_points.top_sellers
                THEN seller_ranked.cumulative_pct_all_extreme_tail_orders
            END
        ) AS cumulative_pct_all_extreme_tail_orders
    FROM concentration_points
    CROSS JOIN seller_ranked
    GROUP BY
        concentration_points.top_sellers
),
combined_output AS (
    SELECT
        1 AS output_sort,
        'seller_detail' AS analysis_level,
        seller_ranked.seller_rank,
        seller_ranked.seller_id,
        seller_ranked.seller_state,
        seller_ranked.long_distance_orders,
        seller_ranked.avg_distance_km,
        seller_ranked.avg_carrier_to_customer_days,
        seller_ranked.extreme_tail_orders,
        ROUND(100.0 * seller_ranked.seller_extreme_tail_rate, 2) AS pct_orders_extreme_tail,
        ROUND(
            seller_ranked.seller_extreme_tail_rate / seller_ranked.overall_extreme_tail_rate,
            2
        ) AS extreme_tail_lift,
        ROUND(seller_ranked.expected_extreme_tail_orders::NUMERIC, 2) AS expected_extreme_tail_orders,
        ROUND(seller_ranked.excess_extreme_tail_orders::NUMERIC, 2) AS excess_extreme_tail_orders,
        ROUND(seller_ranked.pct_all_long_distance_orders::NUMERIC, 2) AS pct_all_long_distance_orders,
        ROUND(seller_ranked.pct_all_extreme_tail_orders::NUMERIC, 2) AS pct_all_extreme_tail_orders,
        ROUND(
            seller_ranked.pct_all_extreme_tail_orders
            / NULLIF(seller_ranked.pct_all_long_distance_orders, 0),
            2
        ) AS tail_concentration_ratio,
        ROUND(seller_ranked.cumulative_pct_all_long_distance_orders::NUMERIC, 2) AS cumulative_pct_all_long_distance_orders,
        ROUND(seller_ranked.cumulative_pct_all_extreme_tail_orders::NUMERIC, 2) AS cumulative_pct_all_extreme_tail_orders,
        ROUND(seller_ranked.overall_p95_carrier_days::NUMERIC, 2) AS overall_p95_carrier_days
    FROM seller_ranked
    WHERE seller_ranked.seller_rank <= 50
    UNION ALL
    SELECT
        2 AS output_sort,
        'top_' || concentration_summary.top_sellers || '_seller_concentration' AS analysis_level,
        NULL::BIGINT AS seller_rank,
        NULL::TEXT AS seller_id,
        NULL::TEXT AS seller_state,
        concentration_summary.long_distance_orders,
        NULL::NUMERIC AS avg_distance_km,
        NULL::NUMERIC AS avg_carrier_to_customer_days,
        concentration_summary.extreme_tail_orders,
        ROUND(
            100.0
            * concentration_summary.extreme_tail_orders
            / NULLIF(concentration_summary.long_distance_orders, 0),
            2
        ) AS pct_orders_extreme_tail,
        ROUND(
            (
                concentration_summary.extreme_tail_orders::NUMERIC
                / NULLIF(concentration_summary.long_distance_orders, 0)
            )
            / concentration_summary.overall_extreme_tail_rate,
            2
        ) AS extreme_tail_lift,
        ROUND(concentration_summary.expected_extreme_tail_orders::NUMERIC, 2) AS expected_extreme_tail_orders,
        ROUND(concentration_summary.excess_extreme_tail_orders::NUMERIC, 2) AS excess_extreme_tail_orders,
        ROUND(concentration_summary.cumulative_pct_all_long_distance_orders::NUMERIC, 2) AS pct_all_long_distance_orders,
        ROUND(concentration_summary.cumulative_pct_all_extreme_tail_orders::NUMERIC, 2) AS pct_all_extreme_tail_orders,
        ROUND(
            concentration_summary.cumulative_pct_all_extreme_tail_orders
            / NULLIF(concentration_summary.cumulative_pct_all_long_distance_orders, 0),
            2
        ) AS tail_concentration_ratio,
        ROUND(concentration_summary.cumulative_pct_all_long_distance_orders::NUMERIC, 2) AS cumulative_pct_all_long_distance_orders,
        ROUND(concentration_summary.cumulative_pct_all_extreme_tail_orders::NUMERIC, 2) AS cumulative_pct_all_extreme_tail_orders,
        ROUND(concentration_summary.overall_p95_carrier_days::NUMERIC, 2) AS overall_p95_carrier_days
    FROM concentration_summary
)
SELECT
    combined_output.analysis_level,
    combined_output.seller_rank,
    combined_output.seller_id,
    combined_output.seller_state,
    combined_output.long_distance_orders,
    combined_output.avg_distance_km,
    combined_output.avg_carrier_to_customer_days,
    combined_output.extreme_tail_orders,
    combined_output.pct_orders_extreme_tail,
    combined_output.extreme_tail_lift,
    combined_output.expected_extreme_tail_orders,
    combined_output.excess_extreme_tail_orders,
    combined_output.pct_all_long_distance_orders,
    combined_output.pct_all_extreme_tail_orders,
    combined_output.tail_concentration_ratio,
    combined_output.cumulative_pct_all_long_distance_orders,
    combined_output.cumulative_pct_all_extreme_tail_orders,
    combined_output.overall_p95_carrier_days
FROM combined_output
ORDER BY
    combined_output.output_sort,
    combined_output.seller_rank NULLS LAST,
    combined_output.analysis_level;