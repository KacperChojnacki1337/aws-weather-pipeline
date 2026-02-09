# AWS Weather Data Pipeline

A production-ready Data Lakehouse project built using the Medallion Architecture. This pipeline automates the ingestion, transformation and analysis of weather data for 18 capital cities in Poland using Infrastructure as Code (IaC).


## 🏗 Architecture Overview
The system is fully automated and follows a three-layer data pattern:

Bronze (Raw Layer):

- Source: Open-Meteo API.

- Ingestion: AWS Lambda triggered hourly by EventBridge.

- Format: Raw JSON files stored in S3.

Silver (Transformed Layer):

- Processing: Triggered by S3 Event Notifications.

- Logic: Python Lambda performs flattening of nested JSON and Strict Schema Enforcement to prevent HIVE_BAD_DATA errors.

- Format: Highly optimized Parquet files partitioned by city, year, month, and day.

Gold (Analytics Layer):

- Discovery: AWS Glue Crawler automatically updates the Data Catalog.

- Consumption: Amazon Athena for SQL queries and daily statistics



## 🛠 Tech Stack
- **Cloud:** AWS (Lambda, S3, EventBridge, IAM, Glue, CloudWatch, SNS)
- **IaC:** Terraform
- **Data Engineering:** Python (Pandas, AWS SDK/Boto3, AWS Wrangler).
- **CI/CD:** GitHub Actions
- **Testing:** Pytest (Unit testing for transformation logic)
- **Storage Format:** Apache Parquet (Columnar storage).

## 📂 Project Structure
.
├── lambda_func/             # AWS Lambda source code
│   ├── __init__.py
│   ├── bronze_ingest.py     # API ingestion logic (Bronze)
│   └── transformer.py       # Data flattening & Parquet conversion (Silver)
├── tests/                   # Unit testing suite
│   ├── __init__.py
│   └── test_transformer.py  # Tests for transformation logic
├── main.tf                  # Primary Terraform configuration (S3, Lambda, Glue)
├── variables.tf             # Infrastructure variables
├── outputs.tf               # Resource ARNs and endpoint outputs
├── .gitignore               # Excludes terraform.tfstate and zip files
└── README.md                # Technical documentation

##🚀 Key Engineering Solutions
- **Schema Enforcement:** Resolved INT64 vs Double type mismatches by explicitly casting metrics to float64 within the Silver Lambda.
- **Cost Optimization:** Implemented S3 Lifecycle Policies to transition raw data to Glacier Instant Retrieval after 30 days and delete after 90 days.
- **Event-Driven Flow:** Fully decoupled layers using S3 Event Notifications to trigger downstream processing automatically.
- **Observability:** Configured CloudWatch Alarms integrated with Amazon SNS to send real-time email notifications upon Lambda execution failures.


## 🚀 Features (Bronze Layer)
- **Automated Ingestion:** Triggered hourly via Amazon EventBridge.
- **Hive-style Partitioning:** Data is organized in S3 as `raw/city=NAME/year=YYYY/month=MM/day=DD/` for optimized querying.
- **Error Handling:** Full logging in AWS CloudWatch and error-catching for API requests.
- **Scalability:** Currently monitoring 18 voivodeship capital cities in Poland.

## ⚙️ Setup & Deployment
1. **Prerequisites:** AWS Account and GitHub Secrets configured (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).
2. **Local Development:**
   ```bash
   terraform init
   terraform plan
   terraform apply
3. CI/CD: Any push to master or develop branches triggers an automatic deployment via GitHub Actions.