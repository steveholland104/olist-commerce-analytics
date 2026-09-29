-- Export query used to create the Tableau Public data source.
--
-- Tableau Public was used for the published portfolio dashboard, so the
-- curated dbt mart was exported from Snowflake as a CSV rather than connected
-- through a persistent live Snowflake connection.

USE ROLE TABLEAU_ROLE;
USE WAREHOUSE OLIST_WH;

SELECT
	*
FROM OLIST_ANALYTICS.DBT_DEV_MARTS.FCT_DELIVERY_ORDERS;