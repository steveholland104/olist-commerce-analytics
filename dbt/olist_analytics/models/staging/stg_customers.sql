with source_customers AS (
	SELECT
		*
	FROM {{ source('raw','customers') }}
),

renamed_customers AS (
	SELECT
		customer_id,
		customer_unique_id,
		customer_zip_code_prefix as customer_zip_prefix,
		customer_city,
		customer_state
	FROM source_customers
)

SELECT
	*
FROM renamed_customers