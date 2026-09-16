-- North inbound state-by-calendar extreme carrier-tail analysis
-- Purpose: Determine whether calendar spikes in long-distance North-region carrier failures are broad across destination states or concentrated in particular states and therefore potentially caused by changing order mix.
-- Long-distance definition: Seller-to-customer distance greater than 1,000 km.
-- Extreme-tail definition: Carrier transit at or above the 95th percentile among all valid long-distance single-seller orders in the analysis period.
-- Calendar period: January 2017 through August 2018.
-- North inbound definition: Customer is in the North region and seller is outside the North region.
-- Important limitation: Geography is a proxy only. The Olist data does not
-- identify actual carrier routes, transportation modes, river crossings, or hubs.

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
customer_region_map AS (
    SELECT
        state_region.state_code AS customer_state,
        state_region.region_name AS customer_region
    FROM state_region
),
seller_region_map AS (
    SELECT
        state_region.state_code AS seller_state,
        state_region.region_name AS seller_region
    FROM state_region
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
        customer_geography.customer_latitude,
        customer_geography.customer_longitude,
        seller_geography.seller_state,
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
        seller_region_map.seller_region,
        order_distance.customer_state,
        customer_region_map.customer_region,
        DATE_TRUNC(
            'month',
            raw.orders.order_purchase_timestamp
        )::DATE AS purchase_month,
        EXTRACT(
            EPOCH FROM (
                raw.orders.order_delivered_customer_date
                - raw.orders.order_delivered_carrier_date
            )
        ) / 86400.0 AS carrier_to_customer_days
    FROM order_distance
    JOIN raw.orders
        ON order_distance.order_id = raw.orders.order_id
    JOIN customer_region_map
        ON order_distance.customer_state = customer_region_map.customer_state
    JOIN seller_region_map
        ON order_distance.seller_state = seller_region_map.seller_state
    WHERE order_distance.distance_km > 1000
        AND raw.orders.order_purchase_timestamp >= '2017-01-01'
        AND raw.orders.order_purchase_timestamp < '2018-09-01'
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
        long_distance_orders.seller_region,
        long_distance_orders.customer_state,
        long_distance_orders.customer_region,
        long_distance_orders.purchase_month,
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
north_inbound_orders AS (
    SELECT
        long_distance_flagged.order_id,
        long_distance_flagged.distance_km,
        long_distance_flagged.seller_state,
        long_distance_flagged.seller_region,
        long_distance_flagged.customer_state,
        long_distance_flagged.purchase_month,
        long_distance_flagged.carrier_to_customer_days,
        long_distance_flagged.extreme_tail,
        long_distance_flagged.p95_carrier_to_customer_days
    FROM long_distance_flagged
    WHERE long_distance_flagged.customer_region = 'North'
        AND long_distance_flagged.seller_region <> 'North'
),
north_state_totals AS (
    SELECT
        north_inbound_orders.customer_state,
        COUNT(*) AS state_long_distance_orders,
        SUM(north_inbound_orders.extreme_tail) AS state_extreme_tail_orders,
        AVG(north_inbound_orders.extreme_tail) AS state_extreme_tail_rate
    FROM north_inbound_orders
    GROUP BY
        north_inbound_orders.customer_state
),
north_month_totals AS (
    SELECT
        north_inbound_orders.purchase_month,
        COUNT(*) AS month_long_distance_orders,
        SUM(north_inbound_orders.extreme_tail) AS month_extreme_tail_orders
    FROM north_inbound_orders
    GROUP BY
        north_inbound_orders.purchase_month
),
north_state_month_summary AS (
    SELECT
        north_inbound_orders.customer_state,
        north_inbound_orders.purchase_month,
        COUNT(*) AS long_distance_orders,
        ROUND(
            AVG(north_inbound_orders.distance_km)::NUMERIC,
            2
        ) AS avg_distance_km,
        ROUND(
            AVG(north_inbound_orders.carrier_to_customer_days)::NUMERIC,
            2
        ) AS avg_carrier_to_customer_days,
        ROUND(
            PERCENTILE_CONT(0.95)
                WITHIN GROUP (
                    ORDER BY north_inbound_orders.carrier_to_customer_days
                )::NUMERIC,
            2
        ) AS p95_carrier_to_customer_days,
        SUM(north_inbound_orders.extreme_tail) AS extreme_tail_orders,
        AVG(north_inbound_orders.extreme_tail) AS month_state_extreme_tail_rate,
        MAX(north_inbound_orders.p95_carrier_to_customer_days) AS overall_p95_carrier_days
    FROM north_inbound_orders
    GROUP BY
        north_inbound_orders.customer_state,
        north_inbound_orders.purchase_month
)
SELECT
    north_state_month_summary.customer_state,
    north_state_month_summary.purchase_month,
    north_state_month_summary.long_distance_orders,
    north_state_month_summary.avg_distance_km,
    north_state_month_summary.avg_carrier_to_customer_days,
    north_state_month_summary.p95_carrier_to_customer_days,
    north_state_month_summary.extreme_tail_orders,
    ROUND(
        100.0 * north_state_month_summary.month_state_extreme_tail_rate,
        2
    ) AS pct_orders_extreme_tail,
    north_state_totals.state_long_distance_orders,
    ROUND(
        100.0 * north_state_totals.state_extreme_tail_rate,
        2
    ) AS state_overall_pct_extreme_tail,
    ROUND(
        north_state_month_summary.month_state_extreme_tail_rate
        / NULLIF(north_state_totals.state_extreme_tail_rate, 0),
        2
    ) AS month_vs_state_tail_lift,
    ROUND(
        100.0
        * north_state_month_summary.long_distance_orders
        / north_month_totals.month_long_distance_orders,
        2
    ) AS pct_of_month_orders,
    ROUND(
        100.0
        * north_state_month_summary.extreme_tail_orders
        / NULLIF(north_month_totals.month_extreme_tail_orders, 0),
        2
    ) AS pct_of_month_extreme_tail_orders,
    ROUND(
        north_state_month_summary.overall_p95_carrier_days::NUMERIC,
        2
    ) AS overall_p95_carrier_days
FROM north_state_month_summary
JOIN north_state_totals
    ON north_state_month_summary.customer_state = north_state_totals.customer_state
JOIN north_month_totals
    ON north_state_month_summary.purchase_month = north_month_totals.purchase_month
ORDER BY
    north_state_month_summary.purchase_month,
    north_state_month_summary.extreme_tail_orders DESC,
    north_state_month_summary.customer_state;