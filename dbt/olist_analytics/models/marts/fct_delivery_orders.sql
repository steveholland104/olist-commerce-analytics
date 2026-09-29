{{ config(
	materialized='incremental',
	unique_key='order_id',
	incremental_strategy='merge',
	on_schema_change='sync_all_columns'
) }}

with order_delivery_analysis AS (
	SELECT
		*
	FROM {{ ref('int_order_delivery_analysis') }}
),

delivery_orders AS (
	SELECT
		order_id,
		customer_id,
		seller_id,
		purchased_at,
		approved_at,
		delivered_to_carrier_at,
		delivered_to_customer_at,
		estimated_delivery_at,

		MONTH(purchased_at)::INT as purchase_month,
		(DAYOFWEEKISO(purchased_at) - 1)::INT as purchase_day_of_week,

		purchase_to_carrier_days,
		carrier_to_customer_days,
		total_delivery_days,
		promised_days_from_purchase,
		days_vs_estimate,
		is_late,

		customer_state,
		seller_state,

		CASE
			WHEN customer_state IS NOT NULL
				AND seller_state IS NOT NULL
			THEN seller_state || '->' || customer_state
		END as state_lane,

		CASE
			WHEN customer_state IS NOT NULL
				AND seller_state IS NOT NULL
			THEN customer_state = seller_state
		END as same_state,

		distance_km,

		item_count,
		distinct_product_count,
		seller_count,
		total_item_value,
		total_freight_value,
		total_weight_g,
		total_volume_cm3,

		distinct_category_count,
		product_category,

		review_count,
		average_review_score,
		minimum_review_score,
		maximum_review_score,
		has_poor_review,
		review_submitted_before_delivery,

		GREATEST_IGNORE_NULLS(
			purchased_at,
			approved_at,
			delivered_to_carrier_at,
			delivered_to_customer_at,
			first_review_created_at,
			last_review_created_at
		) as record_updated_at

	FROM order_delivery_analysis
	WHERE order_status = 'delivered'
		AND has_valid_delivery_chronology = TRUE
),

incremental_delivery_orders AS (
	SELECT
		*
	FROM delivery_orders

	{% if is_incremental() %}

	WHERE record_updated_at >= (
		SELECT
			DATEADD(
				'day',
				-60,
				MAX(record_updated_at)
			)
		FROM {{ this }}
	)
/*

The incremental mart reprocesses a 60-day event-time window. In the historical data, 99% of orders reached their last observed delivery/review event within 47 days of purchase and 99% of reviews were created within 37 days. The additional buffer accommodates unusually long lifecycle events while limiting repeated processing. Because the source does not expose a true update or ingestion timestamp, very late-arriving historical corrections may require a full refresh.

*/


	{% endif %}
)

SELECT
	*
FROM incremental_delivery_orders