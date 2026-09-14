CREATE TABLE IF NOT EXISTS raw.order_items (
    order_id             TEXT,
    order_item_id        INTEGER,
    product_id           TEXT,
    seller_id            TEXT,
    shipping_limit_date  TIMESTAMP,
    price                 NUMERIC(12, 2),
    freight_value         NUMERIC(12, 2)
);
