-- Validation checks for dbt intermediate models and final delivery mart.
-- These queries reconcile transformed outputs to known source populations,
-- confirm model grain, and verify key delivery metrics.

USE ROLE DBT_ROLE;
USE WAREHOUSE OLIST_WH;


/*
1. Geolocation cleanup

Raw geolocation:
19,015 distinct ZIP prefixes

Cleaned intermediate:
19,011 ZIP prefixes after removing implausible coordinates
*/

SELECT
	COUNT(*)::INT as zip_prefix_count,
	MIN(latitude) as minimum_latitude,
	MAX(latitude) as maximum_latitude,
	MIN(longitude) as minimum_longitude,
	MAX(longitude) as maximum_longitude
FROM OLIST_ANALYTICS.DBT_DEV_INTERMEDIATE.INT_GEOLOCATION_ZIP;


/*
2. Order-item rollup

Expected:
98,666 orders represented in order_items
97,388 single-seller orders
1,278 multi-seller orders
*/

SELECT
	COUNT(*)::INT as order_count,
	COUNT_IF(seller_count = 1)::INT as single_seller_orders,
	COUNT_IF(seller_count > 1)::INT as multi_seller_orders,
	MIN(item_count)::INT as minimum_item_count,
	MAX(item_count)::INT as maximum_item_count
FROM OLIST_ANALYTICS.DBT_DEV_INTERMEDIATE.INT_ORDER_ITEMS_ROLLUP;


/*
3. Order geography coverage

Expected:
99,441 total orders
97,388 single-seller orders
1,278 multi-seller orders
775 orders without item rollup
99,162 orders with customer coordinates
97,172 orders with seller coordinates
96,904 single-seller orders with both coordinates
*/

SELECT
	COUNT(*)::INT as order_count,
	COUNT_IF(seller_count = 1)::INT as single_seller_orders,
	COUNT_IF(seller_count > 1)::INT as multi_seller_orders,
	COUNT_IF(seller_count IS NULL)::INT as orders_without_item_rollup,
	COUNT_IF(
		customer_latitude IS NOT NULL
		AND customer_longitude IS NOT NULL
	)::INT as orders_with_customer_coordinates,
	COUNT_IF(
		seller_latitude IS NOT NULL
		AND seller_longitude IS NOT NULL
	)::INT as orders_with_seller_coordinates,
	COUNT_IF(
		seller_count = 1
		AND customer_latitude IS NOT NULL
		AND customer_longitude IS NOT NULL
		AND seller_latitude IS NOT NULL
		AND seller_longitude IS NOT NULL
	)::INT as single_seller_orders_with_both_coordinates
FROM OLIST_ANALYTICS.DBT_DEV_INTERMEDIATE.INT_ORDER_GEOGRAPHY;


/*
4. Seller-to-customer distance validation

Expected:
99,441 total orders
96,904 orders with calculated distance
0 negative distances
*/

SELECT
	COUNT(*)::INT as order_count,
	COUNT(distance_km)::INT as orders_with_distance,
	MIN(distance_km) as minimum_distance_km,
	MAX(distance_km) as maximum_distance_km,
	AVG(distance_km) as average_distance_km,
	MEDIAN(distance_km) as median_distance_km,
	COUNT_IF(distance_km < 0)::INT as negative_distance_count,
	COUNT_IF(distance_km = 0)::INT as zero_distance_count,
	COUNT_IF(distance_km IS NULL)::INT as missing_distance_count
FROM OLIST_ANALYTICS.DBT_DEV_INTERMEDIATE.INT_ORDER_DISTANCE;


/*
5. Delivery timing reconciliation

Expected:
99,441 total orders
96,478 delivered orders
8 delivered orders missing customer-delivery timestamp
96,281 delivered orders with valid chronology
*/

SELECT
	COUNT(*)::INT as order_count,
	COUNT_IF(order_status = 'delivered')::INT as delivered_orders,
	COUNT_IF(
		order_status = 'delivered'
		AND delivered_to_customer_at IS NULL
	)::INT as delivered_missing_customer_timestamp,
	COUNT_IF(
		order_status = 'delivered'
		AND has_valid_delivery_chronology = TRUE
	)::INT as valid_delivered_orders
FROM OLIST_ANALYTICS.DBT_DEV_INTERMEDIATE.INT_DELIVERY_TIMING;


/*
Valid delivered-order timing benchmarks

Expected approximately:
Purchase → Carrier avg 3.23 days
Purchase → Carrier median 2.20 days
Purchase → Carrier P90 6.40 days

Carrier → Customer avg 9.33 days
Carrier → Customer median 7.10 days
Carrier → Customer P90 18.91 days

Total delivery avg 12.57 days
Total delivery median 10.23 days
*/

SELECT
	AVG(purchase_to_carrier_days) as average_purchase_to_carrier_days,

	MEDIAN(purchase_to_carrier_days) as median_purchase_to_carrier_days,

	PERCENTILE_CONT(0.90) WITHIN GROUP (
		ORDER BY purchase_to_carrier_days
	) as p90_purchase_to_carrier_days,

	AVG(carrier_to_customer_days) as average_carrier_to_customer_days,

	MEDIAN(carrier_to_customer_days) as median_carrier_to_customer_days,

	PERCENTILE_CONT(0.90) WITHIN GROUP (
		ORDER BY carrier_to_customer_days
	) as p90_carrier_to_customer_days,

	AVG(total_delivery_days) as average_total_delivery_days,

	MEDIAN(total_delivery_days) as median_total_delivery_days

FROM OLIST_ANALYTICS.DBT_DEV_INTERMEDIATE.INT_DELIVERY_TIMING
	WHERE order_status = 'delivered'
		AND has_valid_delivery_chronology = TRUE;


/*
6. Review aggregation reconciliation

Raw source:
99,224 review records
98,673 reviewed orders
*/

SELECT
	COUNT(*)::INT as reviewed_orders,
	MIN(review_count)::INT as minimum_review_count,
	MAX(review_count)::INT as maximum_review_count,
	SUM(review_count)::INT as total_review_records
FROM OLIST_ANALYTICS.DBT_DEV_INTERMEDIATE.INT_ORDER_REVIEW_SUMMARY;


/*
7. Unified order-level analysis validation

Expected:
99,441 rows
99,441 distinct orders
96,478 delivered orders
96,281 valid delivered orders
96,904 orders with distance
98,673 orders with reviews
*/

SELECT
	COUNT(*)::INT as order_count,
	COUNT(DISTINCT order_id)::INT as distinct_order_count,
	COUNT_IF(order_status = 'delivered')::INT as delivered_orders,
	COUNT_IF(
		order_status = 'delivered'
		AND has_valid_delivery_chronology = TRUE
	)::INT as valid_delivered_orders,
	COUNT(distance_km)::INT as orders_with_distance,
	COUNT_IF(review_count IS NOT NULL)::INT as orders_with_reviews,
	COUNT_IF(has_poor_review = TRUE)::INT as orders_with_poor_reviews,
	COUNT_IF(review_submitted_before_delivery = TRUE)::INT as reviews_before_delivery
FROM OLIST_ANALYTICS.DBT_DEV_INTERMEDIATE.INT_ORDER_DELIVERY_ANALYSIS;


/*
8. Final delivery mart validation

Expected:
96,281 total rows
96,281 distinct orders

The mart contains delivered orders with valid fulfillment chronology.
*/

SELECT
	COUNT(*)::INT as order_count,
	COUNT(DISTINCT order_id)::INT as distinct_order_count,
	MIN(purchased_at) as earliest_purchase,
	MAX(purchased_at) as latest_purchase,
	MIN(record_updated_at) as earliest_record_update,
	MAX(record_updated_at) as latest_record_update,
	COUNT(distance_km)::INT as orders_with_distance,
	COUNT_IF(is_late = TRUE)::INT as late_orders,
	ROUND(
		100.0 * COUNT_IF(is_late = TRUE)::DECIMAL / COUNT(*)::DECIMAL,
		2
	) as late_delivery_rate,
	COUNT_IF(has_poor_review = TRUE)::INT as orders_with_poor_reviews
FROM OLIST_ANALYTICS.DBT_DEV_MARTS.FCT_DELIVERY_ORDERS;