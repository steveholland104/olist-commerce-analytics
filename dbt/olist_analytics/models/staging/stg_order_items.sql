with source_order_items AS (
	SELECT
		*
	FROM {{ source('raw', 'order_items') }}
),

renamed_order_items AS (
	SELECT
		order_id,
		order_item_id,
		product_id,
		seller_id,
		shipping_limit_date as shopping_limit_at,
		price as item_price,
		freight_value
	FROM source_order_items
)

SELECT
	*
FROM renamed_order_items