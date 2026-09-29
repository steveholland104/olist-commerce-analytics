with source_product_category_translation AS (
	SELECT
		*
	FROM {{ source('raw', 'product_category_translation') }}
),

renamed_product_category_translation AS (
	SELECT
		product_category_name,
		product_category_name_english
	FROM source_product_category_translation
)

SELECT
	*
FROM renamed_product_category_translation