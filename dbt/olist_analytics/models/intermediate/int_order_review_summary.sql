with order_reviews AS (
	SELECT
		*
	FROM {{ ref('stg_order_reviews') }}
),

order_review_summary AS (
	SELECT
		order_id,
		COUNT(*)::INT as review_count,
		AVG(review_score) as average_review_score,
		MIN(review_score) as minimum_review_score,
		MAX(review_score) as maximum_review_score,
		MIN(review_created_at) as first_review_created_at,
		MAX(review_created_at) as last_review_created_at,
		MAX(
			CASE
				WHEN review_score <= 2
					THEN 1
				ELSE 0
			END
		)::BOOLEAN as has_poor_review
	FROM order_reviews
	GROUP BY order_id
)

SELECT
	*
FROM order_review_summary