# Prepare the long-distance delivery-tail dataset for predictive modeling.
# Point of this script is to...
# 1. Load the modeling dataset from PostgreSQL
# 2. Select predictor variables and the target
# 3. Separate training and testing data chronologically
# 4. Prepare missing and categorical values for modeling

import os
import pandas

from dotenv import load_dotenv

from sqlalchemy import create_engine
from sqlalchemy.engine import URL

from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import OneHotEncoder
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.metrics import average_precision_score
from sklearn.inspection import permutation_importance

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
	*
FROM analytics.long_distance_tail_model_dataset;
"""

dataframe = pandas.read_sql(query, engine)

# Defining the target variable

target_column = "extreme_tail_full_period"

# Defining the predictor variables available to the model

predictor_columns = [
	"purchase_month",
	"purchase_day_of_week",
	"seller_state",
	"customer_state",
	"state_lane",
	"same_region",
	"distance_km",
	"product_category",
	"item_count",
	"distinct_product_count",
	"total_weight_g",
	"total_volume_cm3",
	"total_item_value",
	"total_freight_value",
	"promised_days_from_purchase"
]

# Create the predictor DataFrame and target series

predictor_dataframe = dataframe[predictor_columns].copy()

target_series = dataframe[target_column].copy()

# Convert purchase data into a pandas datetime value

purchase_date_series = pandas.to_datetime(
	dataframe["purchase_date"]
)

# Define the date separating the training date from future test data

test_start_date = pandas.Timestamp("2018-03-01")

training_rows = purchase_date_series < test_start_date
testing_rows = purchase_date_series >= test_start_date

# Calculate the extreme tail threshold using only the training period

training_tail_threshold = dataframe.loc[
    training_rows,
    "carrier_to_customer_days"
].quantile(0.95)

# Create the modeling target using the training period threshold

model_target_series = (
    dataframe["carrier_to_customer_days"] >= training_tail_threshold
).astype(int)

# Split the predictors and target into training and testing datasets

training_predictor_dataframe = predictor_dataframe[
	training_rows
].copy()

testing_predictor_dataframe = predictor_dataframe[
	testing_rows
].copy()

training_target_series = model_target_series[
	training_rows
].copy()

testing_target_series = model_target_series[
	testing_rows
].copy()

# Compare the extreme tail rate in the training and testing periods

training_extreme_tail_rate = training_target_series.mean()

testing_extreme_tail_rate = testing_target_series.mean()

# Check missing predictor values in the training/testing datasets

#print(training_predictor_dataframe.isna().sum())
#print(testing_predictor_dataframe.isna().sum())

# Separate categorical preditors from numerical

categorical_predictor_columns = [
	"purchase_month",
	"purchase_day_of_week",
	"seller_state",
	"customer_state",
	"state_lane",
	"product_category"
]

numerical_predictor_columns = [
    	"same_region",
    	"distance_km",
    	"item_count",
    	"distinct_product_count",
    	"total_weight_g",
    	"total_volume_cm3",
    	"total_item_value",
    	"total_freight_value",
    	"promised_days_from_purchase"
]

# Define how missing numerical values should be handled

numerical_transformer = Pipeline(
	steps=[
	    (
	    	"imputer",
	    	SimpleImputer(strategy="median")
	    ),
	    (
		"scaler",
		StandardScaler()
	    )
	]
)

categorical_transformer = OneHotEncoder(
    	handle_unknown="infrequent_if_exist",
    	min_frequency=10
)

# Combine the numerical and categorical processing rules

preprocessor = ColumnTransformer(
	transformers=[
	    (
		"numerical",
		numerical_transformer,
		numerical_predictor_columns
	    ),
	    (
		"categorical",
		categorical_transformer,
		categorical_predictor_columns
	    )
	]
)

# Combine preprocessing and logistic regression into one modeling pipeline

model_pipeline = Pipeline(
    steps=[
        (
            "preprocessor",
            preprocessor
        ),
        (
            "model",
            LogisticRegression(
                max_iter=2000
            )
        )
    ]
)

# Train the complete pipeline using the original training predictors

model_pipeline.fit(
    training_predictor_dataframe,
    training_target_series
)

# Predict extreme tail probabilities with the complete pipeline

pipeline_testing_probability = model_pipeline.predict_proba(
    testing_predictor_dataframe
)[:, 1]

pipeline_testing_roc_auc = roc_auc_score(
    testing_target_series,
    pipeline_testing_probability
)

pipeline_testing_average_precision = average_precision_score(
    testing_target_series,
    pipeline_testing_probability
)

# Apply the already learned preprocessing rules to the testing data


model_feature_names = preprocessor.get_feature_names_out()


# Predict the probabilty of extreme tail elivery for the testing data
# Measure how well the model ranks extreme tail orders above normal orders
# Measure precision-recall performance for rate extreme tail class
# Create a testing results DataFrame containing actual outcomes and predicted risk

testing_results_dataframe = pandas.DataFrame(
	{
	    "actual_extreme_tail": testing_target_series,
	    "predicted_extreme_tail_probability": pipeline_testing_probability
	}
)

#print(testing_results_dataframe.head())

# Divide testing orders into 10 equal sized groups based on the predicted risk

testing_results_dataframe["risk_decile"] = pandas.qcut(
	testing_results_dataframe["predicted_extreme_tail_probability"],
	q=10,
	labels=False
)


# Summarize actual extreme tail performance by predicted risk decile

risk_decile_summary = (
    testing_results_dataframe
    .groupby("risk_decile")
    .agg(
	orders=("actual_extreme_tail", "count"),
	extreme_tail_orders=("actual_extreme_tail", "sum"),
	actual_extreme_tail_rate=("actual_extreme_tail", "mean"),
	average_predicted_probability=("predicted_extreme_tail_probability", "mean")
    )
    .reset_index()
)

#print(risk_decile_summary)

# Pair each model feature with the coefficient learned by logistic regression
# Identify categorical values that appear in testing but not in training

#for column in categorical_predictor_columns:
#    training_values = set(training_predictor_dataframe[column].dropna().unique())
#    testing_values = set(testing_predictor_dataframe[column].dropna().unique())#

#    unknown_testing_values = testing_values - training_values

#    if unknown_testing_values:
#        print(column)
 #       print(unknown_testing_values)

# Count testing orders containing categorical values not seen during training

#for column in categorical_predictor_columns:
#    training_values = set(
#        training_predictor_dataframe[column].dropna().unique()
#    )

#    unknown_testing_rows = ~testing_predictor_dataframe[column].isin(
#        training_values
#    )

#    unknown_testing_order_count = unknown_testing_rows.sum()
#    unknown_testing_order_percent = (
#        unknown_testing_order_count
#        / len(testing_predictor_dataframe)
#        * 100
#    )

#    if unknown_testing_order_count > 0:
#        print(column)
#        print("Unknown testing orders:", unknown_testing_order_count)
#        print("Percent of testing orders:", unknown_testing_order_percent)


pipeline_testing_average_precision = average_precision_score(
    testing_target_series,
    pipeline_testing_probability
)


# Measure how much each original predictor contributes to out-of-sample ranking performance.

permutation_importance_result = permutation_importance(
    model_pipeline,
    testing_predictor_dataframe,
    testing_target_series,
    scoring="roc_auc",
    n_repeats=10,
    random_state=42
)

# Create a readable table of permutation importance results

permutation_importance_dataframe = pandas.DataFrame(
    {
        "predictor": predictor_columns,
        "importance_mean": permutation_importance_result.importances_mean,
        "importance_standard_deviation": permutation_importance_result.importances_std
    }
)

permutation_importance_dataframe = (
    permutation_importance_dataframe
    .sort_values(
        by="importance_mean",
        ascending=False
    )
    .reset_index(drop=True)
)

#print(
#    permutation_importance_dataframe.round(4)
#)

# Save row output model scores for future dashboard analysis

scored_testing_orders_dataframe = dataframe.loc[
    testing_rows,
    [
        "order_id",
        "purchase_date",
        "purchase_year_month",
        "seller_state",
        "customer_state",
        "state_lane",
        "same_region",
        "distance_km",
        "product_category",
        "item_count",
        "total_weight_g",
        "total_volume_cm3",
        "total_item_value",
        "total_freight_value",
        "promised_days_from_purchase",
        "carrier_to_customer_days"
    ]
].copy()

scored_testing_orders_dataframe["actual_extreme_tail"] = (
    testing_target_series
)

scored_testing_orders_dataframe["predicted_extreme_tail_probability"] = (
    pipeline_testing_probability
)

scored_testing_orders_dataframe["risk_decile"] = (
    testing_results_dataframe["risk_decile"]
)

# Concise run summary

print("Training tail threshold:")
print(round(training_tail_threshold, 2))

print("Testing ROC AUC:")
print(round(pipeline_testing_roc_auc, 4))

print("Testing average precision:")
print(round(pipeline_testing_average_precision, 4))

print("Saved model outputs to outputs/model/")


# Create a folder for saved model outputs.

os.makedirs(
    "outputs/model",
    exist_ok=True
)

risk_decile_summary.to_csv(
    "outputs/model/risk_decile_summary.csv",
    index=False
)

permutation_importance_dataframe.to_csv(
    "outputs/model/permutation_importance.csv",
    index=False
)

model_metrics_dataframe = pandas.DataFrame(
    {
        "training_tail_threshold_days": [training_tail_threshold],
        "training_extreme_tail_rate": [training_target_series.mean()],
        "testing_extreme_tail_rate": [testing_target_series.mean()],
        "testing_roc_auc": [pipeline_testing_roc_auc],
        "testing_average_precision": [pipeline_testing_average_precision]
    }
)

model_metrics_dataframe.to_csv(
    "outputs/model/model_metrics.csv",
    index=False
)

scored_testing_orders_dataframe.to_csv(
    "outputs/model/scored_testing_orders.csv",
    index=False
)