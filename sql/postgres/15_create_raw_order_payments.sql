CREATE TABLE IF NOT EXISTS raw.order_payments (
    order_id              TEXT,
    payment_sequential    INTEGER,
    payment_type          TEXT,
    payment_installments  INTEGER,
    payment_value         NUMERIC(12, 2)
);
