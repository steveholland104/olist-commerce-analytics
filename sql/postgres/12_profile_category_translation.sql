SELECT
    COUNT(*) AS total_rows,
    COUNT(product_category_name) AS non_null_category_names,
    COUNT(DISTINCT product_category_name) AS unique_category_names
FROM raw.product_category_translation;

SELECT
    COUNT(DISTINCT p.product_category_name) AS product_categories_without_translation
FROM raw.products p
LEFT JOIN raw.product_category_translation t
    ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL;

SELECT DISTINCT
    p.product_category_name
FROM raw.products p
LEFT JOIN raw.product_category_translation t
    ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
ORDER BY p.product_category_name;

SELECT
    COALESCE(
        t.product_category_name_english,
        p.product_category_name,
        'unknown'
    ) AS product_category,
    COUNT(DISTINCT p.product_id) AS products,
    COUNT(DISTINCT oi.order_id) AS orders,
    COUNT(*) AS line_items,
    ROUND(SUM(oi.price), 2) AS item_value
FROM raw.order_items oi
JOIN raw.products p
    ON oi.product_id = p.product_id
LEFT JOIN raw.product_category_translation t
    ON p.product_category_name = t.product_category_name
GROUP BY
    COALESCE(
        t.product_category_name_english,
        p.product_category_name,
        'unknown'
    )
ORDER BY item_value DESC;
