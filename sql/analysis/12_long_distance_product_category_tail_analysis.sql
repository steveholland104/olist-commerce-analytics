-- Long-distance product-category extreme carrier-tail analysis
-- Purpose: Determine whether product category is associated with extreme carrier-transit failures among long-distance orders.
-- Long-distance definition: Seller-to-customer distance greater than 1,000 km.
-- Extreme-tail definition: Carrier transit at or above the 95th percentile among all valid long-distance single-seller orders in the analysis period.
-- Calendar period: January 2017 through August 2018.
-- Category assignment: Orders are included only when all order-item rows map to the same product category, preserving a clean one-order/one-category grain.
-- English category translation is used where available. Portuguese category names are retained when no translation exists (2 examples).
-- Categories with fewer than 75 long-distance orders are excluded from the displayed comparison to reduce noise from very small samples.
-- Important limitation: Product category may proxy for shipment weight, dimensional characteristics, seller mix, geography, fragility, carrier arrangements, or other un-observed logistics factors



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
order_category_rows AS (
    SELECT
        raw.order_items.order_id,
        COALESCE(
            raw.product_category_translation.product_category_name_english,
            raw.products.product_category_name,
            'unknown'
        ) AS product_category,
        raw.products.product_weight_g,
        raw.products.product_length_cm,
        raw.products.product_height_cm,
        raw.products.product_width_cm
    FROM raw.order_items
    JOIN raw.products
        ON raw.order_items.product_id = raw.products.product_id
    LEFT JOIN raw.product_category_translation
        ON raw.products.product_category_name = raw.product_category_translation.product_category_name
),
order_category_count AS (
    SELECT
        order_category_rows.order_id,
        COUNT(DISTINCT order_category_rows.product_category) AS category_count
    FROM order_category_rows
    GROUP BY
        order_category_rows.order_id
),
single_category_order AS (
    SELECT
        order_category_rows.order_id,
        MIN(order_category_rows.product_category) AS product_category,
        COUNT(*) AS item_count,
        CASE
            WHEN COUNT(*) FILTER (WHERE order_category_rows.product_weight_g IS NULL) = 0
            THEN SUM(order_category_rows.product_weight_g)
        END AS total_weight_g,
        CASE
            WHEN COUNT(*) FILTER (
                WHERE order_category_rows.product_length_cm IS NULL
                    OR order_category_rows.product_height_cm IS NULL
                    OR order_category_rows.product_width_cm IS NULL
            ) = 0
            THEN SUM(
                order_category_rows.product_length_cm::NUMERIC
                * order_category_rows.product_height_cm::NUMERIC
                * order_category_rows.product_width_cm::NUMERIC
            )
        END AS total_volume_cm3
    FROM order_category_rows
    JOIN order_category_count
        ON order_category_rows.order_id = order_category_count.order_id
    WHERE order_category_count.category_count = 1
    GROUP BY
        order_category_rows.order_id
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
        single_category_order.product_category,
        single_category_order.item_count,
        single_category_order.total_weight_g,
        single_category_order.total_volume_cm3,
        EXTRACT(
            EPOCH FROM (
                raw.orders.order_delivered_customer_date
                - raw.orders.order_delivered_carrier_date
            )
        ) / 86400.0 AS carrier_to_customer_days
    FROM order_distance
    JOIN raw.orders
        ON order_distance.order_id = raw.orders.order_id
    JOIN single_category_order
        ON order_distance.order_id = single_category_order.order_id
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
        long_distance_orders.product_category,
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
category_summary AS (
    SELECT
        long_distance_flagged.product_category,
        COUNT(*) AS long_distance_orders,
        ROUND(AVG(long_distance_flagged.distance_km)::NUMERIC, 2) AS avg_distance_km,
        ROUND(AVG(long_distance_flagged.item_count)::NUMERIC, 2) AS avg_items_per_order,
        ROUND((AVG(long_distance_flagged.total_weight_g) / 1000.0)::NUMERIC, 2) AS avg_total_weight_kg,
        ROUND((AVG(long_distance_flagged.total_volume_cm3) / 1000.0)::NUMERIC, 2) AS avg_total_volume_liters,
        ROUND(AVG(long_distance_flagged.carrier_to_customer_days)::NUMERIC, 2) AS avg_carrier_to_customer_days,
        ROUND(
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY long_distance_flagged.carrier_to_customer_days)::NUMERIC,
            2
        ) AS p95_carrier_to_customer_days,
        SUM(long_distance_flagged.extreme_tail) AS extreme_tail_orders,
        AVG(long_distance_flagged.extreme_tail) AS category_extreme_tail_rate
    FROM long_distance_flagged
    GROUP BY
        long_distance_flagged.product_category
)
SELECT
    category_summary.product_category,
    category_summary.long_distance_orders,
    category_summary.avg_distance_km,
    category_summary.avg_items_per_order,
    category_summary.avg_total_weight_kg,
    category_summary.avg_total_volume_liters,
    category_summary.avg_carrier_to_customer_days,
    category_summary.p95_carrier_to_customer_days,
    category_summary.extreme_tail_orders,
    ROUND(
        100.0 * category_summary.category_extreme_tail_rate,
        2
    ) AS pct_orders_extreme_tail,
    ROUND(
        category_summary.category_extreme_tail_rate
        / tail_totals.overall_extreme_tail_rate,
        2
    ) AS extreme_tail_lift,
    ROUND(
        category_summary.long_distance_orders::NUMERIC
        * tail_totals.overall_extreme_tail_rate,
        2
    ) AS expected_extreme_tail_orders,
    ROUND(
        (
            category_summary.extreme_tail_orders
            - category_summary.long_distance_orders
            * tail_totals.overall_extreme_tail_rate
        )::NUMERIC,
        2
    ) AS excess_extreme_tail_orders,
    ROUND(
        100.0
        * category_summary.long_distance_orders
        / tail_totals.long_distance_orders,
        2
    ) AS pct_all_long_distance_orders,
    ROUND(
        100.0
        * category_summary.extreme_tail_orders
        / tail_totals.total_extreme_tail_orders,
        2
    ) AS pct_all_extreme_tail_orders,
    ROUND(
        (
            100.0
            * category_summary.extreme_tail_orders
            / tail_totals.total_extreme_tail_orders
        )
        / NULLIF(
            100.0
            * category_summary.long_distance_orders
            / tail_totals.long_distance_orders,
            0
        ),
        2
    ) AS tail_concentration_ratio,
    ROUND(tail_totals.overall_p95_carrier_days::NUMERIC, 2) AS overall_p95_carrier_days
FROM category_summary
CROSS JOIN tail_totals
WHERE category_summary.long_distance_orders >= 75
ORDER BY
    category_summary.extreme_tail_orders DESC,
    category_summary.long_distance_orders DESC,
    category_summary.product_category;