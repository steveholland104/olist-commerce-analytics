SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS distinct_orders,
    COUNT(DISTINCT (order_id, order_item_id)) AS distinct_order_item_keys
FROM raw.order_items;

SELECT
    o.order_status,
    COUNT(*) AS orders_without_items
FROM raw.orders o
LEFT JOIN raw.order_items oi
    ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_items DESC;

SELECT
    COUNT(*) AS order_items_without_order_match
FROM raw.order_items oi
LEFT JOIN raw.orders o
    ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

WITH items_per_order AS (
    SELECT
        order_id,
        COUNT(*) AS item_count
    FROM raw.order_items
    GROUP BY order_id
)

SELECT
    item_count,
    COUNT(*) AS order_count
FROM items_per_order
GROUP BY item_count
ORDER BY item_count;

WITH sellers_per_order AS (
    SELECT
        order_id,
        COUNT(DISTINCT seller_id) AS seller_count
    FROM raw.order_items
    GROUP BY order_id
)

SELECT
    seller_count,
    COUNT(*) AS order_count
FROM sellers_per_order
GROUP BY seller_count
ORDER BY seller_count;
