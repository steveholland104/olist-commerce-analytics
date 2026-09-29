with source_orders AS (
	SELECT
		*
	FROM {{ source('raw','orders') }}
),

renamed_orders AS (
	SELECT
		order_id,
		customer_id,
		order_status,
		order_purchase_timestamp as purchased_at,
		order_approved_at as approved_at,
		order_delivered_carrier_date as delivered_to_carrier_at,
		order_delivered_customer_date as delivered_to_customer_at,
		order_estimated_delivery_date as estimated_delivery_at
	FROM source_orders
)

SELECT
	*
FROM renamed_orders