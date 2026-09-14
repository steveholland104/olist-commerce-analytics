SELECT
    COUNT(*) AS total_rows,
    COUNT(geolocation_zip_code_prefix) AS non_null_zip_prefixes,
    COUNT(DISTINCT geolocation_zip_code_prefix) AS unique_zip_prefixes
FROM raw.geolocation;

WITH observations_per_zip AS (
    SELECT
        geolocation_zip_code_prefix,
        COUNT(*) AS observation_count
    FROM raw.geolocation
    GROUP BY geolocation_zip_code_prefix
)

SELECT
    MIN(observation_count) AS min_observations,
    ROUND(AVG(observation_count), 2) AS avg_observations,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY observation_count
    ) AS median_observations,
    MAX(observation_count) AS max_observations
FROM observations_per_zip;

SELECT
    COUNT(DISTINCT c.customer_zip_code_prefix) AS customer_zip_prefixes,
    COUNT(DISTINCT c.customer_zip_code_prefix) FILTER (
        WHERE g.geolocation_zip_code_prefix IS NOT NULL
    ) AS customer_zip_prefixes_with_geo,
    COUNT(DISTINCT c.customer_zip_code_prefix) FILTER (
        WHERE g.geolocation_zip_code_prefix IS NULL
    ) AS customer_zip_prefixes_without_geo
FROM raw.customers c
LEFT JOIN (
    SELECT DISTINCT geolocation_zip_code_prefix
    FROM raw.geolocation
) g
    ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix;

SELECT
    COUNT(DISTINCT s.seller_zip_code_prefix) AS seller_zip_prefixes,
    COUNT(DISTINCT s.seller_zip_code_prefix) FILTER (
        WHERE g.geolocation_zip_code_prefix IS NOT NULL
    ) AS seller_zip_prefixes_with_geo,
    COUNT(DISTINCT s.seller_zip_code_prefix) FILTER (
        WHERE g.geolocation_zip_code_prefix IS NULL
    ) AS seller_zip_prefixes_without_geo
FROM raw.sellers s
LEFT JOIN (
    SELECT DISTINCT geolocation_zip_code_prefix
    FROM raw.geolocation
) g
    ON s.seller_zip_code_prefix = g.geolocation_zip_code_prefix;

SELECT
    COUNT(*) AS customer_records,
    COUNT(*) FILTER (
        WHERE g.geolocation_zip_code_prefix IS NOT NULL
    ) AS customer_records_with_geo,
    COUNT(*) FILTER (
        WHERE g.geolocation_zip_code_prefix IS NULL
    ) AS customer_records_without_geo
FROM raw.customers c
LEFT JOIN (
    SELECT DISTINCT geolocation_zip_code_prefix
    FROM raw.geolocation
) g
    ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix;

SELECT
    COUNT(*) AS seller_records,
    COUNT(*) FILTER (
        WHERE g.geolocation_zip_code_prefix IS NOT NULL
    ) AS seller_records_with_geo,
    COUNT(*) FILTER (
        WHERE g.geolocation_zip_code_prefix IS NULL
    ) AS seller_records_without_geo
FROM raw.sellers s
LEFT JOIN (
    SELECT DISTINCT geolocation_zip_code_prefix
    FROM raw.geolocation
) g
    ON s.seller_zip_code_prefix = g.geolocation_zip_code_prefix;
