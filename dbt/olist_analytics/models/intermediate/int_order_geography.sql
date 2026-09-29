with orders as (
    SELECT
        *
    FROM {{ ref('stg_orders') }}
),

customers as (
    SELECT
        *
    FROM {{ ref('stg_customers') }}
),

order_items as (
    SELECT
        *
    FROM {{ ref('stg_order_items') }}
),

order_rollup as (
    SELECT
        *
    FROM {{ ref('int_order_items_rollup') }}
),

sellers as (
    SELECT
        *
    FROM {{ ref('stg_sellers') }}
),

geolocation as (
    SELECT
        *
    FROM {{ ref('int_geolocation_zip') }}
),

single_seller_orders as (
    SELECT
        order_id,
        MIN(seller_id) as seller_id
    FROM order_items
        GROUP BY order_id
        HAVING COUNT(distinct seller_id) = 1
),

order_geography as (
    SELECT
            orders.order_id,
            orders.customer_id,
            order_rollup.seller_count,
            single_seller_orders.seller_id,
            customers.customer_zip_prefix,
            customers.customer_city,
            customers.customer_state,
            customer_geolocation.latitude as customer_latitude,
            customer_geolocation.longitude as customer_longitude,
            sellers.seller_zip_prefix,
            sellers.seller_city,
            sellers.seller_state,
            seller_geolocation.latitude as seller_latitude,
            seller_geolocation.longitude as seller_longitude
    FROM orders
        LEFT JOIN customers
            ON orders.customer_id = customers.customer_id
        LEFT JOIN order_rollup
            ON orders.order_id = order_rollup.order_id
        LEFT JOIN single_seller_orders
            ON orders.order_id = single_seller_orders.order_id
        LEFT JOIN sellers
            ON single_seller_orders.seller_id = sellers.seller_id
        LEFT JOIN geolocation as customer_geolocation
            ON customers.customer_zip_prefix = customer_geolocation.geolocation_zip_prefix
        LEFT JOIN geolocation as seller_geolocation
            ON sellers.seller_zip_prefix = seller_geolocation.geolocation_zip_prefix
)

SELECT
    *
FROM order_geography