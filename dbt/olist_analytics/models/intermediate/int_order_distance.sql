with order_geography AS (
	SELECT
		*
	FROM {{ ref('int_order_geography') }}
),

order_distance AS (
	SELECT
		order_id,
		customer_id,
		seller_count,
		seller_id,
		customer_zip_prefix,
		customer_city,
		customer_state,
		customer_latitude,
		customer_longitude,
		seller_zip_prefix,
		seller_city,
		seller_state,
		seller_latitude,
		seller_longitude,
		CASE
			WHEN seller_count = 1
				AND customer_latitude IS NOT NULL
				AND customer_longitude IS NOT NULL
				AND seller_latitude IS NOT NULL
				AND seller_longitude IS NOT NULL
			THEN st_distance(
				st_makepoint(seller_longitude, seller_latitude),
				st_makepoint(customer_longitude, customer_latitude)
			)::DECIMAL / 1000.0::DECIMAL
		END as distance_km
	FROM order_geography
)

SELECT
	*
FROM order_distance