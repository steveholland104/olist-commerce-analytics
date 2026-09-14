SELECT
    COUNT(*) AS total_rows,
    COUNT(customer_id) AS non_null_customer_ids,
    COUNT(DISTINCT customer_id) AS unique_customer_ids,
    COUNT(customer_unique_id) AS non_null_unique_ids,
    COUNT(DISTINCT customer_unique_id) AS unique_customers
FROM raw.customers;

SELECT
    COUNT(*) AS orders_without_customer_match
FROM raw.orders o
LEFT JOIN raw.customers c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

SELECT
    COUNT(*) AS customers_without_order_match
FROM raw.customers c
LEFT JOIN raw.orders o
    ON c.customer_id = o.customer_id
WHERE o.customer_id IS NULL;

WITH customer_order_counts AS (
    SELECT
        customer_unique_id,
        COUNT(*) AS order_count
    FROM raw.customers
    GROUP BY customer_unique_id
)

SELECT
    order_count,
    COUNT(*) AS customer_count
FROM customer_order_counts
GROUP BY order_count
ORDER BY order_count;

SELECT
    customer_state,
    COUNT(*) AS customer_records,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS pct_of_customer_records
FROM raw.customers
GROUP BY customer_state
ORDER BY customer_records DESC;
