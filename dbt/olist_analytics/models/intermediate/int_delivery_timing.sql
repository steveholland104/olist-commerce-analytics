with orders AS (
	SELECT
		*
	FROM {{ ref('stg_orders') }}
),

delivery_timing AS (
	SELECT
		order_id,
		customer_id,
		order_status,
		purchased_at,
		approved_at,
		delivered_to_carrier_at,
		delivered_to_customer_at,
		estimated_delivery_at,

		DATEDIFF(
			'second',
			purchased_at,
			delivered_to_carrier_at
		) / 86400.0 as purchase_to_carrier_days,

		DATEDIFF(
			'second',
			delivered_to_carrier_at,
			delivered_to_customer_at
		) / 86400.0 as carrier_to_customer_days,

		DATEDIFF(
			'second',
			purchased_at,
			delivered_to_customer_at
		) / 86400.0 as total_delivery_days,

		DATEDIFF(
			'second',
			purchased_at,
			estimated_delivery_at
		) / 86400.0 as promised_days_from_purchase,

		DATEDIFF(
			'second',
			estimated_delivery_at,
			delivered_to_customer_at
		) / 86400.0 as days_vs_estimate,

		CASE
			WHEN delivered_to_customer_at IS NOT NULL
				AND estimated_delivery_at IS NOT NULL
			THEN delivered_to_customer_at::DATE > estimated_delivery_at::DATE
		END as is_late,

		CASE
			WHEN purchased_at IS NOT NULL
				AND delivered_to_carrier_at IS NOT NULL
				AND delivered_to_customer_at IS NOT NULL
				AND purchased_at <= delivered_to_carrier_at
				AND delivered_to_carrier_at <= delivered_to_customer_at
			THEN TRUE
			ELSE FALSE
		END as has_valid_delivery_chronology

	FROM orders
)

SELECT
	*
FROM delivery_timing