with source_geolocation AS (
	SELECT
		*
	FROM {{ source('raw','geolocation') }}
),

renamed_geolocation AS (
	SELECT
		geolocation_zip_code_prefix as geolocation_zip_prefix,
		geolocation_lat as latitude,
		geolocation_lng as longitude,
		geolocation_city as city,
		geolocation_state as state
	FROM source_geolocation
)

SELECT
	*
FROM renamed_geolocation