SELECT
    COUNT(*) AS total_rows,
    COUNT(review_id) AS non_null_review_ids,
    COUNT(DISTINCT review_id) AS unique_review_ids,
    COUNT(order_id) AS non_null_order_ids,
    COUNT(DISTINCT order_id) AS distinct_reviewed_orders
FROM raw.order_reviews;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT (review_id, order_id)) AS unique_review_order_pairs
FROM raw.order_reviews;

WITH reviews_per_order AS (
    SELECT
        order_id,
        COUNT(*) AS review_count
    FROM raw.order_reviews
    GROUP BY order_id
)

SELECT
    review_count,
    COUNT(*) AS order_count
FROM reviews_per_order
GROUP BY review_count
ORDER BY review_count;

WITH orders_per_review_id AS (
    SELECT
        review_id,
        COUNT(*) AS row_count,
        COUNT(DISTINCT order_id) AS distinct_orders
    FROM raw.order_reviews
    GROUP BY review_id
)

SELECT
    row_count,
    distinct_orders,
    COUNT(*) AS review_id_count
FROM orders_per_review_id
GROUP BY row_count, distinct_orders
ORDER BY row_count, distinct_orders;

SELECT
    COUNT(*) AS review_rows_without_order_match
FROM raw.order_reviews r
LEFT JOIN raw.orders o
    ON r.order_id = o.order_id
WHERE o.order_id IS NULL;

SELECT
    o.order_status,
    COUNT(*) AS orders_without_review
FROM raw.orders o
LEFT JOIN raw.order_reviews r
    ON o.order_id = r.order_id
WHERE r.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_review DESC;

SELECT
    COUNT(*) AS review_rows,
    COUNT(*) FILTER (
        WHERE review_answer_timestamp IS NULL
    ) AS missing_answer_timestamp,
    COUNT(*) FILTER (
        WHERE review_creation_date IS NULL
    ) AS missing_creation_date,
    COUNT(*) FILTER (
        WHERE review_score IS NULL
    ) AS missing_review_score
FROM raw.order_reviews;

SELECT
    o.order_status,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT r.order_id) AS orders_with_review_record,
    ROUND(
        100.0 * COUNT(DISTINCT r.order_id)
        / COUNT(DISTINCT o.order_id),
        2
    ) AS review_record_pct
FROM raw.orders o
LEFT JOIN raw.order_reviews r
    ON o.order_id = r.order_id
GROUP BY o.order_status
ORDER BY total_orders DESC;

SELECT
    COUNT(*) AS matched_review_rows,
    COUNT(*) FILTER (
        WHERE r.review_creation_date >= o.order_delivered_customer_date
    ) AS created_on_or_after_delivery,
    COUNT(*) FILTER (
        WHERE r.review_creation_date >= o.order_estimated_delivery_date
    ) AS created_on_or_after_estimated_date
FROM raw.order_reviews r
JOIN raw.orders o
    ON r.order_id = o.order_id
WHERE o.order_delivered_customer_date IS NOT NULL;

SELECT
    CASE
        WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
            THEN 'delivered_on_or_before_estimate'
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 'delivered_late'
    END AS delivery_status,
    COUNT(*) AS review_rows,
    COUNT(*) FILTER (
        WHERE r.review_creation_date >= o.order_delivered_customer_date
    ) AS created_on_or_after_delivery,
    COUNT(*) FILTER (
        WHERE r.review_creation_date >= o.order_estimated_delivery_date
    ) AS created_on_or_after_estimate
FROM raw.order_reviews r
JOIN raw.orders o
    ON r.order_id = o.order_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY 1
ORDER BY 1;

SELECT
    review_score,
    COUNT(*) AS review_count,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS pct_of_reviews
FROM raw.order_reviews
GROUP BY review_score
ORDER BY review_score;

SELECT
    COUNT(*) AS total_reviews,
    COUNT(*) FILTER (
        WHERE review_comment_title IS NOT NULL
    ) AS reviews_with_title,
    COUNT(*) FILTER (
        WHERE review_comment_message IS NOT NULL
    ) AS reviews_with_message,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE review_comment_message IS NOT NULL
        ) / COUNT(*),
        2
    ) AS pct_with_message
FROM raw.order_reviews;
