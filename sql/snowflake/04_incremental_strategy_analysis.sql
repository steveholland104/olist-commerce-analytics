-- Analysis used to select the incremental lookback window for
-- OLIST_ANALYTICS.DBT_DEV_MARTS.FCT_DELIVERY_ORDERS.
--
-- Historical results:
-- Purchase → last known event: P95 = 31 days, P99 = 47 days, max = 210 days
-- Purchase → review:          P95 = 29 days, P99 = 37 days, max = 148 days
--
-- A 60-day lookback was selected to exceed the observed 99th-percentile
-- lifecycle lag while limiting unnecessary reprocessing.
--
-- Limitation:
-- The Olist source does not provide a true source-system updated_at or
-- ingestion timestamp. Very late-arriving historical corrections may therefore
-- require a full refresh.

USE ROLE DBT_ROLE;
USE WAREHOUSE OLIST_WH;


/*
Purchase to last observed operational/review event
*/

SELECT
	MAX(
		DATEDIFF(
			'day',
			purchased_at,
			GREATEST_IGNORE_NULLS(
				delivered_to_customer_at,
				first_review_created_at,
				last_review_created_at
			)
		)
	) AS maximum_purchase_to_last_event_days,
	PERCENTILE_CONT(0.95) WITHIN GROUP (
		ORDER BY DATEDIFF(
			'day',
			purchased_at,
			GREATEST_IGNORE_NULLS(
				delivered_to_customer_at,
				first_review_created_at,
				last_review_created_at
			)
		)
	) AS p95_purchase_to_last_event_days,
	PERCENTILE_CONT(0.99) WITHIN GROUP (
		ORDER BY DATEDIFF(
			'day',
			purchased_at,
			GREATEST_IGNORE_NULLS(
				delivered_to_customer_at,
				first_review_created_at,
				last_review_created_at
			)
		)
	) AS p99_purchase_to_last_event_days
FROM OLIST_ANALYTICS.DBT_DEV_INTERMEDIATE.INT_ORDER_DELIVERY_ANALYSIS;


/*
Purchase to latest review event
*/

SELECT
	MAX(
		DATEDIFF(
			'day',
			purchased_at,
			last_review_created_at
		)
	) AS maximum_purchase_to_review_days,
	PERCENTILE_CONT(0.95) WITHIN GROUP (
		ORDER BY DATEDIFF(
			'day',
			purchased_at,
			last_review_created_at
		)
	) AS p95_purchase_to_review_days,
	PERCENTILE_CONT(0.99) WITHIN GROUP (
		ORDER BY DATEDIFF(
			'day',
			purchased_at,
			last_review_created_at
		)
	) AS p99_purchase_to_review_days
FROM OLIST_ANALYTICS.DBT_DEV_INTERMEDIATE.INT_ORDER_DELIVERY_ANALYSIS
	WHERE last_review_created_at IS NOT NULL;