-- Validation checks for the nine raw Olist source tables loaded into Snowflake.
-- Expected row counts were reconciled against the original source CSV files.

USE ROLE DBT_ROLE;
USE WAREHOUSE OLIST_WH;


/*
Raw table row counts

Expected:
CUSTOMERS                     99,441
SELLERS                        3,095
ORDERS                        99,441
ORDER_ITEMS                  112,650
PRODUCTS                      32,951
PRODUCT_CATEGORY_TRANSLATION      72
ORDER_PAYMENTS               103,886
ORDER_REVIEWS                 99,224
GEOLOCATION                1,000,163
*/

SELECT
	'CUSTOMERS' as table_name,
	COUNT(*)::INT as row_count
FROM OLIST_ANALYTICS.RAW.CUSTOMERS

UNION ALL

SELECT
	'SELLERS' as table_name,
	COUNT(*)::INT as row_count
FROM OLIST_ANALYTICS.RAW.SELLERS

UNION ALL

SELECT
	'ORDERS' as table_name,
	COUNT(*)::INT as row_count
FROM OLIST_ANALYTICS.RAW.ORDERS

UNION ALL

SELECT
	'ORDER_ITEMS' as table_name,
	COUNT(*)::INT as row_count
FROM OLIST_ANALYTICS.RAW.ORDER_ITEMS

UNION ALL

SELECT
	'PRODUCTS' as table_name,
	COUNT(*)::INT as row_count
FROM OLIST_ANALYTICS.RAW.PRODUCTS

UNION ALL

SELECT
	'PRODUCT_CATEGORY_TRANSLATION' as table_name,
	COUNT(*)::INT as row_count
FROM OLIST_ANALYTICS.RAW.PRODUCT_CATEGORY_TRANSLATION

UNION ALL

SELECT
	'ORDER_PAYMENTS' as table_name,
	COUNT(*)::INT as row_count
FROM OLIST_ANALYTICS.RAW.ORDER_PAYMENTS

UNION ALL

SELECT
	'ORDER_REVIEWS' as table_name,
	COUNT(*)::INT as row_count
FROM OLIST_ANALYTICS.RAW.ORDER_REVIEWS

UNION ALL

SELECT
	'GEOLOCATION' as table_name,
	COUNT(*)::INT as row_count
FROM OLIST_ANALYTICS.RAW.GEOLOCATION

ORDER BY table_name;


/*
Core source-grain validation
*/

SELECT
	COUNT(*)::INT as order_count,
	COUNT(DISTINCT order_id)::INT as distinct_order_count
FROM OLIST_ANALYTICS.RAW.ORDERS;


SELECT
	COUNT(*)::INT as customer_count,
	COUNT(DISTINCT customer_id)::INT as distinct_customer_count,
	COUNT(DISTINCT customer_unique_id)::INT as distinct_customer_unique_count
FROM OLIST_ANALYTICS.RAW.CUSTOMERS;


SELECT
	COUNT(*)::INT as order_item_count,
	COUNT(DISTINCT order_id)::INT as distinct_order_count
FROM OLIST_ANALYTICS.RAW.ORDER_ITEMS;


SELECT
	COUNT(*)::INT as seller_count,
	COUNT(DISTINCT seller_id)::INT as distinct_seller_count
FROM OLIST_ANALYTICS.RAW.SELLERS;


SELECT
	COUNT(*)::INT as product_count,
	COUNT(DISTINCT product_id)::INT as distinct_product_count
FROM OLIST_ANALYTICS.RAW.PRODUCTS;


SELECT
	COUNT(*)::INT as review_record_count,
	COUNT(DISTINCT order_id)::INT as reviewed_order_count
FROM OLIST_ANALYTICS.RAW.ORDER_REVIEWS;


SELECT
	COUNT(*)::INT as geolocation_record_count,
	COUNT(DISTINCT geolocation_zip_prefix)::INT as distinct_zip_prefix_count
FROM OLIST_ANALYTICS.RAW.GEOLOCATION;