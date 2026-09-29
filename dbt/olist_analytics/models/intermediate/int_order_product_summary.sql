with order_items AS (
	SELECT
		*
	FROM {{ ref('stg_order_items') }}
),

products AS (
	SELECT
		*
	FROM {{ ref('stg_products') }}
),

category_translation AS (
	SELECT
		*
	FROM {{ ref('stg_product_category_translation') }}
),

order_product_details AS (
	SELECT
		order_items.order_id,
		order_items.product_id,
		COALESCE(
			category_translation.product_category_name_english,
			products.product_category_name
		) as product_category
	FROM order_items
		LEFT JOIN products
			ON order_items.product_id = products.product_id
		LEFT JOIN category_translation
			ON products.product_category_name = category_translation.product_category_name
),

order_product_summary AS (
	SELECT
		order_id,
		COUNT(DISTINCT product_category)::INT as distinct_category_count,
		CASE
			WHEN COUNT(DISTINCT product_category) = 1
			THEN MIN(product_category)
		END as product_category
	FROM order_product_details
		GROUP BY order_id
)

SELECT
	*
FROM order_product_summary