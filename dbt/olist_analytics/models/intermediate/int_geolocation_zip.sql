with valid_geolocation AS (
	SELECT
		geolocation_zip_prefix,
		latitude,
		longitude
	FROM {{ ref('stg_geolocation') }}
		WHERE latitude between -35 and 6
			AND longitude between -75 and -30
),

geolocation_by_zip as (
	SELECT
		geolocation_zip_prefix,
		median(latitude) as latitude,
		median(longitude) as longitude,
		count(*)::INT as geolocation_observation_count
	FROM valid_geolocation
		GROUP BY geolocation_zip_prefix
)

SELECT
	*
FROM geolocation_by_zip