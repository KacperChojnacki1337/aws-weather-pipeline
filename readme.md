# AWS Weather Data Pipeline

A production-ready Data Lakehouse project built using the Medallion Architecture. This pipeline automates the ingestion, transformation, and analysis of weather data for multiple cities in Poland using Infrastructure as Code (IaC).

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

- Consumption: Amazon Athena Views and CTAS tables.

- Insight: Aggregated daily statistics (min/max/avg temperatures) ready for BI tools like QuickSight.



## 🛠 Tech Stack
- **Cloud:** AWS (Lambda, S3, EventBridge, IAM, Glue, CloudWatch)
- **IaC:** Terraform
- **Data Engineering:** Python (Pandas, AWS SDK/Boto3, AWS Wrangler).
- **CI/CD:** GitHub Actions
- **Storage Format:** Apache Parquet (Columnar storage).

## 📂 Project Structure
.
├── lambda/                         # Lambda function source code
│   ├── bronze_ingest.py            # API data ingestion (Bronze Layer)
│   └── transformer.py              # Parquet transformation & type validation (Silver Layer)
├── terraform/                      # Infrastructure as Code (IaC)
│   ├── main.tf                     # Main resources (S3, Lambda, Glue, EventBridge)
│   ├── variables.tf                # Variable definitions
│   ├── outputs.tf                  # Infrastructure outputs (Bucket names, Role ARNs)
│   └── provider.tf                 # AWS Provider configuration
├── .github/workflows/              # CI/CD Automation
│   └── terraform.yml               # Infrastructure deployment pipeline via GitHub Actions
├── .gitignore                      # Ignored files (e.g., lambda.zip, terraform state files)
└── README.md                       # Technical project documentation

##🚀 Key Engineering Solutions
- **Schema Enforcement:** Solved a critical INT64 vs Double type mismatch in Athena by explicitly casting API responses to float64 within the Silver Lambda.
- **Cost Optimization:** Utilized Parquet columnar format and Hive-style partitioning to minimize data scanning costs in Amazon Athena.
- **Event-Driven Flow:** Fully decoupled layers using S3 Event Notifications to trigger downstream processing automatically.


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