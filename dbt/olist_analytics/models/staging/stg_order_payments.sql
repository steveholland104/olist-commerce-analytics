with source_order_payments AS (
	SELECT
		*
	FROM {{ source('raw', 'order_payments') }}
),

renamed_order_payments AS (
	SELECT
		order_id,
		payment_sequential,
		payment_type,
		payment_installments,
		payment_value
	FROM source_order_payments
)

SELECT
	*
FROM renamed_order_payments