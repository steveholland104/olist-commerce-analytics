-- Validation queries used to reconcile the Tableau Public dashboards
-- against the curated Snowflake delivery mart.
--
-- These checks reproduce the primary KPIs and analytical views shown in:
--   1. Executive Delivery Reliability
--   2. Delivery Risk & Diagnostics

USE ROLE TABLEAU_ROLE;
USE WAREHOUSE OLIST_WH;


/*
1. Executive KPI validation

Expected:
Delivered Orders       96,281
Late Delivery Rate       6.8%
Poor Review Rate         12.8%
Average Delivery Time    12.6 days

Poor Review Rate is calculated only among reviewed orders.
*/

SELECT
	COUNT(DISTINCT order_id)::INT as delivered_orders,
	ROUND(
		100.0 * COUNT_IF(is_late = TRUE)
		/ COUNT(DISTINCT order_id),
		1
	) as late_delivery_rate,
	ROUND(
		100.0 * COUNT(DISTINCT CASE
			WHEN has_poor_review = TRUE
			THEN order_id
		END)::DECIMAL
		/ COUNT(DISTINCT CASE
			WHEN review_count IS NOT NULL
			THEN order_id
		END)::DECIMAL,
		1
	) as poor_review_rate,
	ROUND(
		AVG(total_delivery_days),
		1
	) as average_delivery_days
FROM OLIST_ANALYTICS.DBT_DEV_MARTS.FCT_DELIVERY_ORDERS;


/*
2. Poor review rate by delivery status

Expected:
Late
	Delivered Orders: 6,531
	Reviewed Orders:  6,378
	Poor Reviews:     3,985
	Poor Review Rate: 62.48%

On Time
	Delivered Orders: 89,750
	Reviewed Orders:  89,258
	Poor Reviews:      8,301
	Poor Review Rate:  9.30%
*/

SELECT
	CASE
		WHEN is_late = TRUE THEN 'Late'
		ELSE 'On Time'
	END as delivery_status,
	COUNT(DISTINCT order_id)::INT as delivered_orders,
	COUNT(DISTINCT CASE
		WHEN review_count IS NOT NULL
		THEN order_id
	END)::INT as reviewed_orders,
	COUNT(DISTINCT CASE
		WHEN has_poor_review = TRUE
		THEN order_id
	END)::INT as poor_review_orders,
	ROUND(
		100.0 * COUNT(DISTINCT CASE
			WHEN has_poor_review = TRUE
			THEN order_id
		END)
		/ COUNT(DISTINCT CASE
			WHEN review_count IS NOT NULL
			THEN order_id
		END),
		2
	) as poor_review_rate
FROM OLIST_ANALYTICS.DBT_DEV_MARTS.FCT_DELIVERY_ORDERS
	GROUP BY delivery_status
	ORDER BY delivery_status;


/*
3. Late delivery rate by distance

Expected:
0–100 km       17,675 orders    4.51% late
100–500 km     36,406 orders    6.19% late
500–1,000 km   25,325 orders    7.22% late
1,000–2,000 km  9,591 orders    9.61% late
2,000+ km        5,561 orders   12.10% late
Unknown          1,723 orders    3.37% late
*/

with distance_buckets AS (

	SELECT
		order_id,
		is_late,
		CASE
			WHEN distance_km IS NULL THEN 'Unknown'
			WHEN distance_km < 100 THEN '0–100 km'
			WHEN distance_km < 500 THEN '100–500 km'
			WHEN distance_km < 1000 THEN '500–1,000 km'
			WHEN distance_km < 2000 THEN '1,000–2,000 km'
			ELSE '2,000+ km'
		END as distance_bucket,
		CASE
			WHEN distance_km IS NULL THEN 6
			WHEN distance_km < 100 THEN 1
			WHEN distance_km < 500 THEN 2
			WHEN distance_km < 1000 THEN 3
			WHEN distance_km < 2000 THEN 4
			ELSE 5
		END as distance_bucket_sort
	FROM OLIST_ANALYTICS.DBT_DEV_MARTS.FCT_DELIVERY_ORDERS

)

SELECT
	distance_bucket,
	COUNT(DISTINCT order_id)::INT as delivered_orders,
	COUNT_IF(is_late = TRUE)::INT as late_orders,
	ROUND(
		100.0 * COUNT_IF(is_late = TRUE)::DECIMAL
		/ COUNT(DISTINCT order_id)::DECIMAL,
		2
	) as late_delivery_rate
FROM distance_buckets
	GROUP BY distance_bucket,
		distance_bucket_sort
	ORDER BY distance_bucket_sort;


/*
4. Delivery stage duration by distance

Expected averages approximately:

0–100 km
	Purchase → Carrier: 3.17 days
	Carrier → Customer: 3.35 days

100–500 km
	Purchase → Carrier: 3.20 days
	Carrier → Customer: 8.37 days

500–1,000 km
	Purchase → Carrier: 3.28 days
	Carrier → Customer: 11.10 days

1,000–2,000 km
	Purchase → Carrier: 3.36 days
	Carrier → Customer: 14.66 days

2,000+ km
	Purchase → Carrier: 3.46 days
	Carrier → Customer: 17.76 days
*/

with distance_buckets AS (

	SELECT
		*,
		CASE
			WHEN distance_km < 100 THEN '0–100 km'
			WHEN distance_km < 500 THEN '100–500 km'
			WHEN distance_km < 1000 THEN '500–1,000 km'
			WHEN distance_km < 2000 THEN '1,000–2,000 km'
			ELSE '2,000+ km'
		END as distance_bucket,
		CASE
			WHEN distance_km < 100 THEN 1
			WHEN distance_km < 500 THEN 2
			WHEN distance_km < 1000 THEN 3
			WHEN distance_km < 2000 THEN 4
			ELSE 5
		END as distance_bucket_sort
	FROM OLIST_ANALYTICS.DBT_DEV_MARTS.FCT_DELIVERY_ORDERS
		WHERE distance_km IS NOT NULL

)

SELECT
	distance_bucket,
	ROUND(
		AVG(purchase_to_carrier_days),
		2
	) as average_purchase_to_carrier_days,
	ROUND(
		AVG(carrier_to_customer_days),
		2
	) as average_carrier_to_customer_days
FROM distance_buckets
	GROUP BY distance_bucket,
		distance_bucket_sort
	ORDER BY distance_bucket_sort;


/*
5. Late delivery rate by customer state

The Tableau views exclude states with fewer than 300 delivered orders
to avoid emphasizing very small populations.

Highest late-delivery rates among states meeting that threshold included:
AL 21.41%
MA 17.51%
SE 15.27%
PI 13.95%
CE 13.77%
*/

SELECT
	customer_state,
	COUNT(DISTINCT order_id)::INT as delivered_orders,
	COUNT_IF(is_late = TRUE)::INT as late_orders,
	ROUND(
		100.0 * COUNT_IF(is_late = TRUE)
		/ COUNT(DISTINCT order_id),
		2
	) as late_delivery_rate
FROM OLIST_ANALYTICS.DBT_DEV_MARTS.FCT_DELIVERY_ORDERS
	GROUP BY customer_state
	HAVING COUNT(DISTINCT order_id) >= 300
	ORDER BY late_delivery_rate DESC;


/*
6. Monthly late delivery trend

The dashboard begins in January 2017 to avoid visually emphasizing
the very small earliest monthly populations.

March 2018 is the most prominent deterioration in the dashboard,
with an overall late-delivery rate of approximately 19.0%.
*/

SELECT
	DATE_TRUNC(
		'month',
		purchased_at
	) as purchase_month,
	COUNT(DISTINCT order_id)::INT as delivered_orders,
	COUNT_IF(is_late = TRUE)::INT as late_orders,
	ROUND(
		100.0 * COUNT_IF(is_late = TRUE)
		/ COUNT(DISTINCT order_id),
		2
	) as late_delivery_rate
FROM OLIST_ANALYTICS.DBT_DEV_MARTS.FCT_DELIVERY_ORDERS
	WHERE purchased_at >= '2017-01-01'

GROUP BY
	purchase_month

ORDER BY
	purchase_month;