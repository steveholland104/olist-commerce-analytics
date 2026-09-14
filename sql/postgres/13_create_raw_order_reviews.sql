CREATE TABLE IF NOT EXISTS raw.order_reviews (
    review_id                TEXT,
    order_id                 TEXT,
    review_score             INTEGER,
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TIMESTAMP,
    review_answer_timestamp  TIMESTAMP
);
