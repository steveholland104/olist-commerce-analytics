SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS distinct_orders,
    COUNT(DISTINCT (order_id, payment_sequential)) AS distinct_payment_keys
FROM raw.order_payments;

SELECT
    o.order_id,
    o.order_status
FROM raw.orders o
LEFT JOIN raw.order_payments p
    ON o.order_id = p.order_id
WHERE p.order_id IS NULL;

SELECT
    COUNT(*) AS payment_rows_without_order_match
FROM raw.order_payments p
LEFT JOIN raw.orders o
    ON p.order_id = o.order_id
WHERE o.order_id IS NULL;

WITH payments_per_order AS (
    SELECT
        order_id,
        COUNT(*) AS payment_count
    FROM raw.order_payments
    GROUP BY order_id
)

SELECT
    payment_count,
    COUNT(*) AS order_count
FROM payments_per_order
GROUP BY payment_count
ORDER BY payment_count;

SELECT
    payment_type,
    COUNT(*) AS payment_rows,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(SUM(payment_value), 2) AS payment_value
FROM raw.order_payments
GROUP BY payment_type
ORDER BY payment_value DESC;

WITH item_totals AS (
    SELECT
        order_id,
        SUM(price) AS item_value,
        SUM(freight_value) AS freight_value,
        SUM(price + freight_value) AS expected_payment_value
    FROM raw.order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS actual_payment_value
    FROM raw.order_payments
    GROUP BY order_id
)

SELECT
    COUNT(*) AS matched_orders,
    COUNT(*) FILTER (
        WHERE ABS(i.expected_payment_value - p.actual_payment_value) < 0.01
    ) AS exact_matches,
    COUNT(*) FILTER (
        WHERE ABS(i.expected_payment_value - p.actual_payment_value) >= 0.01
    ) AS mismatches,
    ROUND(
        MAX(ABS(i.expected_payment_value - p.actual_payment_value)),
        2
    ) AS largest_difference
FROM item_totals i
JOIN payment_totals p
    ON i.order_id = p.order_id;

WITH item_totals AS (
    SELECT
        order_id,
        SUM(price + freight_value) AS expected_payment_value
    FROM raw.order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        SUM(payment_value) AS actual_payment_value
    FROM raw.order_payments
    GROUP BY order_id
),
differences AS (
    SELECT
        i.order_id,
        i.expected_payment_value,
        p.actual_payment_value,
        p.actual_payment_value - i.expected_payment_value AS difference
    FROM item_totals i
    JOIN payment_totals p
        ON i.order_id = p.order_id
    WHERE ABS(
        p.actual_payment_value - i.expected_payment_value
    ) >= 0.01
)

SELECT
    CASE
        WHEN difference > 0 THEN 'payment_greater_than_items'
        WHEN difference < 0 THEN 'payment_less_than_items'
        ELSE 'equal'
    END AS difference_direction,
    COUNT(*) AS order_count,
    ROUND(MIN(ABS(difference)), 2) AS smallest_difference,
    ROUND(AVG(ABS(difference)), 2) AS avg_difference,
    ROUND(MAX(ABS(difference)), 2) AS largest_difference
FROM differences
GROUP BY 1
ORDER BY order_count DESC;
