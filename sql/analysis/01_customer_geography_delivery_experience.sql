-- Exploratory customer geography analysis
-- Purpose: Identify where delivery-promise failures and customers are reviewing before receiving their orders are concentrated geographically.
-- Grain: One row per delivered order before state-level aggregation.

WITH latest_review AS (
    SELECT
        raw.order_reviews.order_id,
        raw.order_reviews.review_score,
        raw.order_reviews.review_answer_timestamp,
        ROW_NUMBER()
            OVER (
                PARTITION BY raw.order_reviews.order_id
                ORDER BY
                    raw.order_reviews.review_answer_timestamp DESC,
                    raw.order_reviews.review_id DESC
            ) AS review_rank
    FROM raw.order_reviews
), order_level AS (
    SELECT
        raw.orders.order_id,
        raw.customers.customer_state,
        raw.orders.order_delivered_customer_date,
        raw.orders.order_estimated_delivery_date,
        latest_review.review_score,
        latest_review.review_answer_timestamp,
        raw.orders.order_delivered_customer_date::DATE
            - raw.orders.order_estimated_delivery_date::DATE
            AS days_vs_estimate,
        CASE
            WHEN raw.orders.order_delivered_customer_date::DATE
                > raw.orders.order_estimated_delivery_date::DATE
            THEN 1
            ELSE 0
        END AS order_was_late,
        CASE
            WHEN raw.orders.order_delivered_customer_date::DATE
                - raw.orders.order_estimated_delivery_date::DATE > 10
            THEN 1
            ELSE 0
        END AS order_was_severely_late,
	CASE
	    WHEN latest_review.review_answer_timestamp IS NULL
   	 	THEN NULL
    	    WHEN latest_review.review_answer_timestamp
        	< raw.orders.order_delivered_customer_date
    		THEN 1
    	    ELSE 0
	END AS review_before_delivery,
	CASE
    	    WHEN latest_review.review_score IS NULL
    	        THEN NULL
    	    WHEN latest_review.review_score <= 2
    	        THEN 1
    	    ELSE 0
	END AS poor_review
    FROM raw.orders
    JOIN raw.customers
        ON raw.orders.customer_id = raw.customers.customer_id
    LEFT JOIN latest_review
        ON raw.orders.order_id = latest_review.order_id
        AND latest_review.review_rank = 1
    WHERE raw.orders.order_status = 'delivered'
        AND raw.orders.order_delivered_customer_date IS NOT NULL
        AND raw.orders.order_estimated_delivery_date IS NOT NULL
), state_summary AS (
    SELECT
        order_level.customer_state,
        COUNT(*) AS delivered_orders,
        ROUND(
            AVG(order_level.review_score),
            2
        ) AS avg_review_score,
        ROUND(
            100.0 * AVG(order_level.poor_review),
            2
        ) AS pct_poor_review,
        ROUND(
            100.0 * AVG(order_level.order_was_late),
            2
        ) AS pct_late,
        ROUND(
            100.0 * AVG(order_level.order_was_severely_late),
            2
        ) AS pct_more_than_10_days_late,
        COUNT(*) FILTER (
            WHERE order_level.order_was_late = 1
                AND order_level.review_before_delivery = 1
        ) AS late_and_reviewed_before_delivery,
        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE order_level.order_was_late = 1
                    AND order_level.review_before_delivery = 1
            )
            / COUNT(*),
            2
        ) AS pct_all_orders_late_and_reviewed_before_delivery,
        ROUND(
            100.0
            * COUNT(*) FILTER (
                WHERE order_level.order_was_late = 1
                    AND order_level.review_before_delivery = 1
            )
            / NULLIF(
                COUNT(*) FILTER (
                    WHERE order_level.order_was_late = 1
                ),
                0
            ),
            2
        ) AS pct_late_orders_reviewed_before_delivery,
       COUNT(order_level.review_score) AS reviewed_orders
    FROM order_level
    GROUP BY
        order_level.customer_state
)

SELECT
    state_summary.customer_state,
    state_summary.delivered_orders,
    state_summary.reviewed_orders,
    state_summary.avg_review_score,
    state_summary.pct_poor_review,
    state_summary.pct_late,
    state_summary.pct_more_than_10_days_late,
    state_summary.late_and_reviewed_before_delivery,
    state_summary.pct_all_orders_late_and_reviewed_before_delivery,
    state_summary.pct_late_orders_reviewed_before_delivery
FROM state_summary
ORDER BY
    state_summary.pct_all_orders_late_and_reviewed_before_delivery DESC;