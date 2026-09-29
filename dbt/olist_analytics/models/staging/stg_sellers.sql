with source_sellers AS (
	SELECT
		*
	FROM {{ source('raw', 'sellers') }}
),

renamed_sellers AS (
	SELECT
		seller_id,
		seller_zip_code_prefix as seller_zip_prefix,
		seller_city,
		seller_state
	FROM source_sellers
)

SELECT
	*
FROM renamed_sellers