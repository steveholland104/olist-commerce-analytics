-- Long-distance extreme carrier-tail modeling dataset
-- Purpose: Create a reusable one-row-per-order dataset for multivariate modeling of extreme long-distance carrier-transit risk.
-- Long-distance definition: Seller-to-customer distance greater than 1,000 km.
-- Extreme-tail definition: Carrier transit at or above the 95th percentile among all valid long-distance single-seller orders in the analysis period.
-- Calendar period: January 2017 through August 2018.
-- The view contains both predictor candidates and outcome-validation fields.
--
-- Modeling note: Carrier_to_customer_days and p95_carrier_to_customer_days describe the outcome and MUST NOT be used as predictors of extreme_tail_full_period.
--
-- The full-period extreme-tail flag preserves the same target definition used throughout analyses 05-12. When we build the Python model, we will discuss whether to retain this fixed business definition or calculate the threshold using the training period only for a stricter out-of-sample test.
--
-- Product category: Single-category orders retain their translated English category where available. Orders containing multiple categories are labeled multi_category.
-- Missing categories are retained as unknown.
--
-- Product dimensions: Total volume is the sum of item-level length x height x width and should be treated as a product-characteristic proxy, not guaranteed packaged volume.


CREATE SCHEMA IF NOT EXISTS analytics;

CREATE OR REPLACE VIEW analytics.long_distance_tail_model_dataset AS


WITH state_region(state_code, region_name) AS (
    VALUES
        ('AC', 'North'),
        ('AP', 'North'),
        ('AM', 'North'),
        ('PA', 'North'),
        ('RO', 'North'),
        ('RR', 'North'),
        ('TO', 'North'),
        ('AL', 'Northeast'),
        ('BA', 'Northeast'),
        ('CE', 'Northeast'),
        ('MA', 'Northeast'),
        ('PB', 'Northeast'),
        ('PE', 'Northeast'),
        ('PI', 'Northeast'),
        ('RN', 'Northeast'),
        ('SE', 'Northeast'),
        ('DF', 'Central-West'),
        ('GO', 'Central-West'),
        ('MT', 'Central-West'),
        ('MS', 'Central-West'),
        ('ES', 'Southeast'),
        ('MG', 'Southeast'),
        ('RJ', 'Southeast'),
        ('SP', 'Southeast'),
        ('PR', 'South'),
        ('RS', 'South'),
        ('SC', 'South')
),
zip_geography AS (
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
order_item_features AS (
    SELECT
        raw.order_items.order_id,
        COUNT(*) AS item_count,
        COUNT(DISTINCT raw.order_items.product_id) AS distinct_product_count,
        COUNT(
            DISTINCT COALESCE(
                raw.product_category_translation.product_category_name_english,
                raw.products.product_category_name,
                'unknown'
            )
        ) AS product_category_count,
        CASE
            WHEN COUNT(
                DISTINCT COALESCE(
                    raw.product_category_translation.product_category_name_english,
                    raw.products.product_category_name,
                    'unknown'
                )
            ) = 1
            THEN MIN(
                COALESCE(
                    raw.product_category_translation.product_category_name_english,
                    raw.products.product_category_name,
                    'unknown'
                )
            )
            ELSE 'multi_category'
        END AS product_category,
        SUM(raw.order_items.price) AS total_item_value,
        SUM(raw.order_items.freight_value) AS total_freight_value,
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
    LEFT JOIN raw.product_category_translation
        ON raw.products.product_category_name = raw.product_category_translation.product_category_name
    GROUP BY
        raw.order_items.order_id
),
order_geography AS (
    SELECT
        raw.orders.order_id,
        single_seller_order.seller_id,
        seller_geography.seller_state,
        seller_geography.seller_zip_code_prefix,
        seller_geography.seller_latitude,
        seller_geography.seller_longitude,
        customer_geography.customer_state,
        customer_geography.customer_zip_code_prefix,
        customer_geography.customer_latitude,
        customer_geography.customer_longitude
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
        order_geography.seller_zip_code_prefix,
        order_geography.seller_latitude,
        order_geography.seller_longitude,
        order_geography.customer_state,
        order_geography.customer_zip_code_prefix,
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
long_distance_orders AS (
    SELECT
        order_distance.order_id,
        order_distance.seller_id,
        order_distance.seller_state,
        seller_region.region_name AS seller_region,
        order_distance.seller_zip_code_prefix,
        order_distance.seller_latitude,
        order_distance.seller_longitude,
        order_distance.customer_state,
        customer_region.region_name AS customer_region,
        order_distance.customer_zip_code_prefix,
        order_distance.customer_latitude,
        order_distance.customer_longitude,
        order_distance.distance_km,
        order_item_features.item_count,
        order_item_features.distinct_product_count,
        order_item_features.product_category_count,
        order_item_features.product_category,
        order_item_features.total_item_value,
        order_item_features.total_freight_value,
        order_item_features.total_weight_g,
        order_item_features.total_volume_cm3,
        raw.orders.order_purchase_timestamp,
        raw.orders.order_purchase_timestamp::DATE AS purchase_date,
        DATE_TRUNC('month', raw.orders.order_purchase_timestamp)::DATE AS purchase_year_month,
        EXTRACT(YEAR FROM raw.orders.order_purchase_timestamp)::INTEGER AS purchase_year,
        EXTRACT(MONTH FROM raw.orders.order_purchase_timestamp)::INTEGER AS purchase_month,
        EXTRACT(DOW FROM raw.orders.order_purchase_timestamp)::INTEGER AS purchase_day_of_week,
        raw.orders.order_estimated_delivery_date::DATE AS estimated_delivery_date,
        raw.orders.order_estimated_delivery_date::DATE
            - raw.orders.order_purchase_timestamp::DATE AS promised_days_from_purchase,
        order_item_features.total_freight_value
            / order_distance.distance_km
            * 1000.0 AS freight_per_1000_km,
        100.0
            * order_item_features.total_freight_value
            / NULLIF(order_item_features.total_item_value, 0) AS freight_pct_item_value,
        EXTRACT(
            EPOCH FROM (
                raw.orders.order_delivered_customer_date
                - raw.orders.order_delivered_carrier_date
            )
        ) / 86400.0 AS carrier_to_customer_days
    FROM order_distance
    JOIN raw.orders
        ON order_distance.order_id = raw.orders.order_id
    JOIN order_item_features
        ON order_distance.order_id = order_item_features.order_id
    JOIN state_region AS seller_region
        ON order_distance.seller_state = seller_region.state_code
    JOIN state_region AS customer_region
        ON order_distance.customer_state = customer_region.state_code
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
)
SELECT
    long_distance_orders.order_id,
    long_distance_orders.purchase_date,
    long_distance_orders.purchase_year_month,
    long_distance_orders.purchase_year,
    long_distance_orders.purchase_month,
    long_distance_orders.purchase_day_of_week,
    long_distance_orders.seller_id,
    long_distance_orders.seller_state,
    long_distance_orders.seller_region,
    long_distance_orders.seller_zip_code_prefix,
    long_distance_orders.seller_latitude,
    long_distance_orders.seller_longitude,
    long_distance_orders.customer_state,
    long_distance_orders.customer_region,
    long_distance_orders.customer_zip_code_prefix,
    long_distance_orders.customer_latitude,
    long_distance_orders.customer_longitude,
    long_distance_orders.seller_state || '->' || long_distance_orders.customer_state AS state_lane,
    CASE
        WHEN long_distance_orders.seller_state = long_distance_orders.customer_state
        THEN 1
        ELSE 0
    END AS same_state,
    CASE
        WHEN long_distance_orders.seller_region = long_distance_orders.customer_region
        THEN 1
        ELSE 0
    END AS same_region,
    ROUND(long_distance_orders.distance_km::NUMERIC, 2) AS distance_km,
    long_distance_orders.product_category,
    long_distance_orders.product_category_count,
    long_distance_orders.item_count,
    long_distance_orders.distinct_product_count,
    long_distance_orders.total_weight_g,
    long_distance_orders.total_volume_cm3,
    long_distance_orders.total_item_value,
    long_distance_orders.total_freight_value,
    ROUND(long_distance_orders.freight_per_1000_km::NUMERIC, 2) AS freight_per_1000_km,
    ROUND(long_distance_orders.freight_pct_item_value::NUMERIC, 2) AS freight_pct_item_value,
    long_distance_orders.estimated_delivery_date,
    long_distance_orders.promised_days_from_purchase,
    ROUND(long_distance_orders.carrier_to_customer_days::NUMERIC, 4) AS carrier_to_customer_days,
    ROUND(tail_threshold.p95_carrier_to_customer_days::NUMERIC, 4) AS p95_carrier_to_customer_days,
    CASE
        WHEN long_distance_orders.carrier_to_customer_days >= tail_threshold.p95_carrier_to_customer_days
        THEN 1
        ELSE 0
    END AS extreme_tail_full_period
FROM long_distance_orders
CROSS JOIN tail_threshold;

-- QA summary
-- This should return one row and lets us validate the modeling dataset without
-- printing all ~15,000 order-level records to Terminal.
SELECT
    COUNT(*) AS model_rows,
    COUNT(DISTINCT analytics.long_distance_tail_model_dataset.order_id) AS distinct_orders,
    COUNT(*)
        - COUNT(DISTINCT analytics.long_distance_tail_model_dataset.order_id) AS duplicate_order_rows,
    SUM(analytics.long_distance_tail_model_dataset.extreme_tail_full_period) AS extreme_tail_orders,
    ROUND(
        100.0
        * AVG(analytics.long_distance_tail_model_dataset.extreme_tail_full_period),
        2
    ) AS pct_extreme_tail,
    ROUND(
        MIN(analytics.long_distance_tail_model_dataset.p95_carrier_to_customer_days),
        2
    ) AS target_threshold_days,
    MIN(analytics.long_distance_tail_model_dataset.purchase_date) AS first_purchase_date,
    MAX(analytics.long_distance_tail_model_dataset.purchase_date) AS last_purchase_date,
    COUNT(*) FILTER (
        WHERE analytics.long_distance_tail_model_dataset.total_weight_g IS NULL
    ) AS missing_weight_orders,
    COUNT(*) FILTER (
        WHERE analytics.long_distance_tail_model_dataset.total_volume_cm3 IS NULL
    ) AS missing_volume_orders
FROM analytics.long_distance_tail_model_dataset;