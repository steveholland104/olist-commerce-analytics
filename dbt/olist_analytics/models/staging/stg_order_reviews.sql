with source_order_reviews AS (
	SELECT
		*
	FROM {{ source('raw', 'order_reviews') }}
),

renamed_order_reviews AS (
	SELECT
		review_id,
		order_id,
		review_score,
		review_comment_title,
		review_comment_message,
		review_creation_date as review_created_at,
		review_answer_timestamp as review_answered_at
	FROM source_order_reviews
)

SELECT
	*
FROM renamed_order_reviews