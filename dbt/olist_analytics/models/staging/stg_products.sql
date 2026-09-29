with source_products AS (
	SELECT
		*
	FROM {{ source('raw', 'products') }}
),

renamed_products AS (
	SELECT
		product_id,
		product_category_name,
		product_name_lenght as product_name_length,
		product_description_lenght as product_description_length,
		product_photos_qty as product_photo_count,
		product_weight_g,
		product_length_cm,
		product_height_cm,
		product_width_cm
	FROM source_products
)

SELECT
	*
FROM renamed_products