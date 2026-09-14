SELECT
    COUNT(*) AS total_rows,
    COUNT(product_id) AS non_null_product_ids,
    COUNT(DISTINCT product_id) AS unique_product_ids
FROM raw.products;

SELECT
    COUNT(*) FILTER (WHERE product_category_name IS NULL) AS missing_category,
    COUNT(*) FILTER (WHERE product_name_lenght IS NULL) AS missing_name_length,
    COUNT(*) FILTER (WHERE product_description_lenght IS NULL) AS missing_description_length,
    COUNT(*) FILTER (WHERE product_photos_qty IS NULL) AS missing_photos_qty,
    COUNT(*) FILTER (WHERE product_weight_g IS NULL) AS missing_weight,
    COUNT(*) FILTER (WHERE product_length_cm IS NULL) AS missing_length,
    COUNT(*) FILTER (WHERE product_height_cm IS NULL) AS missing_height,
    COUNT(*) FILTER (WHERE product_width_cm IS NULL) AS missing_width
FROM raw.products;

SELECT
    COUNT(DISTINCT oi.product_id) AS order_item_products_without_match
FROM raw.order_items oi
LEFT JOIN raw.products p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;
