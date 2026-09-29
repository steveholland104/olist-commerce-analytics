with order_items as (
    SELECT
        *
    FROM {{ ref('stg_order_items') }}
),

products as (
    SELECT
        *
    FROM {{ ref('stg_products') }}
),

order_item_details as (
    SELECT
            order_items.order_id,
            order_items.order_item_id,
            order_items.product_id,
            order_items.seller_id,
            order_items.item_price,
            order_items.freight_value,
            products.product_weight_g,
            products.product_length_cm,
            products.product_height_cm,
            products.product_width_cm
    FROM order_items
        LEFT JOIN products
            ON order_items.product_id = products.product_id
),

order_rollup as (
    SELECT
            order_id,
            COUNT(*)::INT as item_count,
            COUNT(distinct product_id)::INT as distinct_product_count,
            COUNT(distinct seller_id)::INT as seller_count,
            SUM(item_price) as total_item_value,
            SUM(freight_value) as total_freight_value,
            SUM(product_weight_g) as total_weight_g,
            SUM(
                    product_length_cm
                *
                    product_height_cm
                *
                    product_width_cm
            ) as total_volume_cm3
    FROM order_item_details
        GROUP BY order_id
)

SELECT
    *
FROM order_rollup