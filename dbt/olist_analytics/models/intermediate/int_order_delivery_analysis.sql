with delivery_timing AS (
	SELECT
		*
	FROM {{ ref('int_delivery_timing') }}
),

order_distance AS (
	SELECT
		*
	FROM {{ ref('int_order_distance') }}
),

order_items AS (
	SELECT
		*
	FROM {{ ref('int_order_items_rollup') }}
),

order_reviews AS (
	SELECT
		*
	FROM {{ ref('int_order_review_summary') }}
),

order_products AS (
	SELECT
		*
	FROM {{ ref('int_order_product_summary') }}
),

order_delivery_analysis AS (
	SELECT
		delivery_timing.order_id,
		delivery_timing.customer_id,
		delivery_timing.order_status,
		delivery_timing.purchased_at,
		delivery_timing.approved_at,
		delivery_timing.delivered_to_carrier_at,
		delivery_timing.delivered_to_customer_at,
		delivery_timing.estimated_delivery_at,
		delivery_timing.purchase_to_carrier_days,
		delivery_timing.carrier_to_customer_days,
		delivery_timing.total_delivery_days,
		delivery_timing.promised_days_from_purchase,
		delivery_timing.days_vs_estimate,
		delivery_timing.is_late,
		delivery_timing.has_valid_delivery_chronology,


		order_distance.seller_count,
		order_distance.seller_id,
		order_distance.customer_zip_prefix,
		order_distance.customer_city,
		order_distance.customer_state,
		order_distance.customer_latitude,
		order_distance.customer_longitude,
		order_distance.seller_zip_prefix,
		order_distance.seller_city,
		order_distance.seller_state,
		order_distance.seller_latitude,
		order_distance.seller_longitude,
		order_distance.distance_km,


		order_items.item_count,
		order_items.distinct_product_count,
		order_items.total_item_value,
		order_items.total_freight_value,
		order_items.total_weight_g,
		order_items.total_volume_cm3,


		order_products.distinct_category_count,
		order_products.product_category,


		order_reviews.review_count,
		order_reviews.average_review_score,
		order_reviews.minimum_review_score,
		order_reviews.maximum_review_score,
		order_reviews.first_review_created_at,
		order_reviews.last_review_created_at,
		order_reviews.has_poor_review,



		CASE
			WHEN order_reviews.first_review_created_at IS NOT NULL
				AND delivery_timing.delivered_to_customer_at IS NOT NULL
			THEN order_reviews.first_review_created_at < delivery_timing.delivered_to_customer_at
		END as review_submitted_before_delivery

	FROM delivery_timing
		LEFT JOIN order_distance
			ON delivery_timing.order_id = order_distance.order_id
		LEFT JOIN order_items
			ON delivery_timing.order_id = order_items.order_id
		LEFT JOIN order_products
			ON delivery_timing.order_id = order_products.order_id
		LEFT JOIN order_reviews
			ON delivery_timing.order_id = order_reviews.order_id
)

SELECT
	*
FROM order_delivery_analysis