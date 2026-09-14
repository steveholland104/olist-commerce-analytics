CREATE TABLE IF NOT EXISTS raw.orders (
    order_id                         TEXT,
    customer_id                      TEXT,
    order_status                     TEXT,
    order_purchase_timestamp         TIMESTAMP,
    order_approved_at                TIMESTAMP,
    order_delivered_carrier_date     TIMESTAMP,
    order_delivered_customer_date    TIMESTAMP,
    order_estimated_delivery_date    TIMESTAMP
);
