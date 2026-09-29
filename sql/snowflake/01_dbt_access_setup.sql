-- Snowflake access configuration for dbt.
-- dbt connects through a dedicated service user and least-privilege role.
-- RSA key material and local credential configuration are intentionally
-- excluded from the repository.

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS DBT_ROLE;

CREATE USER IF NOT EXISTS DBT_USER
	TYPE = SERVICE
	DEFAULT_ROLE = DBT_ROLE
	DEFAULT_WAREHOUSE = OLIST_WH;

GRANT ROLE DBT_ROLE
	TO USER DBT_USER;

GRANT ROLE DBT_ROLE
	TO ROLE SYSADMIN;


/*
Key-pair authentication is configured separately from this repository.

Example only:

ALTER USER DBT_USER
	SET RSA_PUBLIC_KEY = '<PUBLIC_KEY_BODY>';

The private key, passphrase, Snowflake account identifier, and local dbt
profile are not stored in source control.
*/


USE ROLE SYSADMIN;

GRANT USAGE
	ON WAREHOUSE OLIST_WH
	TO ROLE DBT_ROLE;

GRANT USAGE
	ON DATABASE OLIST_ANALYTICS
	TO ROLE DBT_ROLE;

GRANT USAGE
	ON SCHEMA OLIST_ANALYTICS.RAW
	TO ROLE DBT_ROLE;

GRANT SELECT
	ON ALL TABLES IN SCHEMA OLIST_ANALYTICS.RAW
	TO ROLE DBT_ROLE;

GRANT SELECT
	ON FUTURE TABLES IN SCHEMA OLIST_ANALYTICS.RAW
	TO ROLE DBT_ROLE;

GRANT CREATE SCHEMA
	ON DATABASE OLIST_ANALYTICS
	TO ROLE DBT_ROLE;