# Test the connection between Python and the PostgreSQL database.
# Database credentials are loaded from the local .env file rather than being written directly into this Python file.

import os
import pandas
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.engine import URL

load_dotenv()

database_user = os.getenv("POSTGRES_USER")
database_password = os.getenv("POSTGRES_PASSWORD")
database_name = os.getenv("POSTGRES_DB")

database_url = URL.create(
    drivername="postgresql+psycopg2",
    username=database_user,
    password=database_password,
    host="localhost",
    port=5432,
    database=database_name
)

engine = create_engine(database_url)

query = """
SELECT
    order_id,
    purchase_date,
    seller_state,
    customer_state,
    distance_km,
    extreme_tail_full_period
FROM analytics.long_distance_tail_model_dataset
LIMIT 5;
"""

dataframe = pandas.read_sql(query, engine)

print(dataframe)