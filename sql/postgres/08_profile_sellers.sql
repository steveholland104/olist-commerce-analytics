SELECT
    COUNT(*) AS total_rows,
    COUNT(seller_id) AS non_null_seller_ids,
    COUNT(DISTINCT seller_id) AS unique_seller_ids
FROM raw.sellers;

SELECT
    COUNT(DISTINCT oi.seller_id) AS order_item_sellers_without_match
FROM raw.order_items oi
LEFT JOIN raw.sellers s
    ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;

SELECT
    seller_state,
    COUNT(*) AS seller_count,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS pct_of_sellers
FROM raw.sellers
GROUP BY seller_state
ORDER BY seller_count DESC;

SELECT
    s.seller_state,
    COUNT(DISTINCT s.seller_id) AS active_sellers,
    COUNT(DISTINCT oi.order_id) AS orders,
    COUNT(*) AS line_items,
    ROUND(SUM(oi.price), 2) AS item_value,
    ROUND(SUM(oi.freight_value), 2) AS freight_value
FROM raw.order_items oi
JOIN raw.sellers s
    ON oi.seller_id = s.seller_id
GROUP BY s.seller_state
ORDER BY item_value DESC;
