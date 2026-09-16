# Inspect the full long-distance modeling dataset in pandas.
# This script loads all rows from the PostgreSQL view and checks: row count, column count, column names, data types, missing values, and a small sample of the data


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
SELECT *
FROM analytics.long_distance_tail_model_dataset;
"""

dataframe = pandas.read_sql(query, engine)

print("DATASET SHAPE")
print(dataframe.shape)

print("\nCOLUMN NAMES")
print(dataframe.columns.tolist())

print("\nDATA TYPES")
print(dataframe.dtypes)

print("\nMISSING VALUES")
print(dataframe.isna().sum())

print("\nFIRST FIVE ROWS")
print(dataframe.head())