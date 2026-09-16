-- Long-distance package-characteristics extreme carrier-tail analysis
-- Purpose: Determine whether heavier or bulkier orders are disproportionately represented in extreme carrier-transit failures among long-distance orders.
-- Long-distance definition: Seller-to-customer distance greater than 1,000 km.
-- Extreme-tail definition: Carrier transit at or above the 95th percentile among all valid long-distance single-seller orders in the analysis period.
-- Calendar period: January 2017 through August 2018.
-- Weight definition: Sum of product weight across all order-item rows.
-- Volume definition: Sum of product length x height x width across order-item rows.
-- Physical-characteristic analysis includes only orders where every item has non-null weight and dimensional data.
-- Quintiles are calculated independently for total order weight and total volume.
-- Important limitation: Product dimensions describe item dimensions in the source data and may not equal the final dimensions used in packaged shipments.

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
order_physical_characteristics AS (
    SELECT
        raw.order_items.order_id,
        COUNT(*) AS item_count,
        CASE
            WHEN COUNT(*) FILTER (WHERE raw.products.product_weight_g IS NULL) = 0
            THEN SUM(raw.products.product_weight_g)
        END AS total_weight_g,
        CASE
            WHEN COUNT(*) FILTER (
                WHERE raw.products.product_length_cm IS NULL
                    OR raw.products.product_height_cm IS NULL
                    OR raw.products.product_width_cm IS NULL
            ) = 0
            THEN SUM(
                raw.products.product_length_cm::NUMERIC
                * raw.products.product_height_cm::NUMERIC
                * raw.products.product_width_cm::NUMERIC
            )
        END AS total_volume_cm3
    FROM raw.order_items
    JOIN raw.products
        ON raw.order_items.product_id = raw.products.product_id
    GROUP BY
        raw.order_items.order_id
),
order_geography AS (
    SELECT
        raw.orders.order_id,
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
        order_physical_characteristics.item_count,
        order_physical_characteristics.total_weight_g,
        order_physical_characteristics.total_volume_cm3,
        EXTRACT(
            EPOCH FROM (
                raw.orders.order_delivered_customer_date
                - raw.orders.order_delivered_carrier_date
            )
        ) / 86400.0 AS carrier_to_customer_days
    FROM order_distance
    JOIN raw.orders
        ON order_distance.order_id = raw.orders.order_id
    JOIN order_physical_characteristics
        ON order_distance.order_id = order_physical_characteristics.order_id
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
        long_distance_orders.distance_km,
        long_distance_orders.item_count,
        long_distance_orders.total_weight_g,
        long_distance_orders.total_volume_cm3,
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
        MAX(long_distance_flagged.p95_carrier_to_customer_days) AS overall_p95_carrier_days
    FROM long_distance_flagged
),
physical_complete_orders AS (
    SELECT
        long_distance_flagged.order_id,
        long_distance_flagged.distance_km,
        long_distance_flagged.item_count,
        long_distance_flagged.total_weight_g,
        long_distance_flagged.total_volume_cm3,
        long_distance_flagged.carrier_to_customer_days,
        long_distance_flagged.extreme_tail,
        long_distance_flagged.p95_carrier_to_customer_days
    FROM long_distance_flagged
    WHERE long_distance_flagged.total_weight_g IS NOT NULL
        AND long_distance_flagged.total_weight_g > 0
        AND long_distance_flagged.total_volume_cm3 IS NOT NULL
        AND long_distance_flagged.total_volume_cm3 > 0
),
physical_coverage AS (
    SELECT
        COUNT(*) AS physical_complete_orders
    FROM physical_complete_orders
),
ranked_physical_orders AS (
    SELECT
        physical_complete_orders.order_id,
        physical_complete_orders.distance_km,
        physical_complete_orders.item_count,
        physical_complete_orders.total_weight_g,
        physical_complete_orders.total_volume_cm3,
        physical_complete_orders.carrier_to_customer_days,
        physical_complete_orders.extreme_tail,
        physical_complete_orders.p95_carrier_to_customer_days,
        NTILE(5) OVER (
            ORDER BY physical_complete_orders.total_weight_g
        ) AS weight_quintile,
        NTILE(5) OVER (
            ORDER BY physical_complete_orders.total_volume_cm3
        ) AS volume_quintile
    FROM physical_complete_orders
),
weight_summary AS (
    SELECT
        1 AS analysis_sort,
        'total_weight_kg' AS analysis_dimension,
        ranked_physical_orders.weight_quintile AS quintile,
        ROUND((MIN(ranked_physical_orders.total_weight_g) / 1000.0)::NUMERIC, 2) AS min_characteristic_value,
        ROUND((MAX(ranked_physical_orders.total_weight_g) / 1000.0)::NUMERIC, 2) AS max_characteristic_value,
        ROUND((AVG(ranked_physical_orders.total_weight_g) / 1000.0)::NUMERIC, 2) AS avg_characteristic_value,
        COUNT(*) AS long_distance_orders,
        ROUND(AVG(ranked_physical_orders.distance_km)::NUMERIC, 2) AS avg_distance_km,
        ROUND(AVG(ranked_physical_orders.item_count)::NUMERIC, 2) AS avg_items_per_order,
        ROUND(AVG(ranked_physical_orders.carrier_to_customer_days)::NUMERIC, 2) AS avg_carrier_to_customer_days,
        ROUND(
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ranked_physical_orders.carrier_to_customer_days)::NUMERIC,
            2
        ) AS p95_carrier_to_customer_days,
        SUM(ranked_physical_orders.extreme_tail) AS extreme_tail_orders,
        ROUND(100.0 * AVG(ranked_physical_orders.extreme_tail), 2) AS pct_orders_extreme_tail
    FROM ranked_physical_orders
    GROUP BY
        ranked_physical_orders.weight_quintile
),
volume_summary AS (
    SELECT
        2 AS analysis_sort,
        'total_volume_liters' AS analysis_dimension,
        ranked_physical_orders.volume_quintile AS quintile,
        ROUND((MIN(ranked_physical_orders.total_volume_cm3) / 1000.0)::NUMERIC, 2) AS min_characteristic_value,
        ROUND((MAX(ranked_physical_orders.total_volume_cm3) / 1000.0)::NUMERIC, 2) AS max_characteristic_value,
        ROUND((AVG(ranked_physical_orders.total_volume_cm3) / 1000.0)::NUMERIC, 2) AS avg_characteristic_value,
        COUNT(*) AS long_distance_orders,
        ROUND(AVG(ranked_physical_orders.distance_km)::NUMERIC, 2) AS avg_distance_km,
        ROUND(AVG(ranked_physical_orders.item_count)::NUMERIC, 2) AS avg_items_per_order,
        ROUND(AVG(ranked_physical_orders.carrier_to_customer_days)::NUMERIC, 2) AS avg_carrier_to_customer_days,
        ROUND(
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ranked_physical_orders.carrier_to_customer_days)::NUMERIC,
            2
        ) AS p95_carrier_to_customer_days,
        SUM(ranked_physical_orders.extreme_tail) AS extreme_tail_orders,
        ROUND(100.0 * AVG(ranked_physical_orders.extreme_tail), 2) AS pct_orders_extreme_tail
    FROM ranked_physical_orders
    GROUP BY
        ranked_physical_orders.volume_quintile
),
combined_summary AS (
    SELECT
        weight_summary.analysis_sort,
        weight_summary.analysis_dimension,
        weight_summary.quintile,
        weight_summary.min_characteristic_value,
        weight_summary.max_characteristic_value,
        weight_summary.avg_characteristic_value,
        weight_summary.long_distance_orders,
        weight_summary.avg_distance_km,
        weight_summary.avg_items_per_order,
        weight_summary.avg_carrier_to_customer_days,
        weight_summary.p95_carrier_to_customer_days,
        weight_summary.extreme_tail_orders,
        weight_summary.pct_orders_extreme_tail
    FROM weight_summary
    UNION ALL
    SELECT
        volume_summary.analysis_sort,
        volume_summary.analysis_dimension,
        volume_summary.quintile,
        volume_summary.min_characteristic_value,
        volume_summary.max_characteristic_value,
        volume_summary.avg_characteristic_value,
        volume_summary.long_distance_orders,
        volume_summary.avg_distance_km,
        volume_summary.avg_items_per_order,
        volume_summary.avg_carrier_to_customer_days,
        volume_summary.p95_carrier_to_customer_days,
        volume_summary.extreme_tail_orders,
        volume_summary.pct_orders_extreme_tail
    FROM volume_summary
)
SELECT
    combined_summary.analysis_dimension,
    combined_summary.quintile,
    combined_summary.min_characteristic_value,
    combined_summary.max_characteristic_value,
    combined_summary.avg_characteristic_value,
    combined_summary.long_distance_orders,
    combined_summary.avg_distance_km,
    combined_summary.avg_items_per_order,
    combined_summary.avg_carrier_to_customer_days,
    combined_summary.p95_carrier_to_customer_days,
    combined_summary.extreme_tail_orders,
    combined_summary.pct_orders_extreme_tail,
    ROUND(
        (combined_summary.pct_orders_extreme_tail / 100.0)
        / tail_totals.overall_extreme_tail_rate,
        2
    ) AS extreme_tail_lift,
    ROUND(
        100.0
        * combined_summary.extreme_tail_orders
        / tail_totals.total_extreme_tail_orders,
        2
    ) AS pct_of_all_extreme_tail_orders,
    physical_coverage.physical_complete_orders,
    ROUND(
        100.0
        * physical_coverage.physical_complete_orders
        / tail_totals.long_distance_orders,
        2
    ) AS pct_orders_with_complete_physical_data,
    ROUND(tail_totals.overall_p95_carrier_days::NUMERIC, 2) AS overall_p95_carrier_days
FROM combined_summary
CROSS JOIN tail_totals
CROSS JOIN physical_coverage
ORDER BY
    combined_summary.analysis_sort,
    combined_summary.quintile;