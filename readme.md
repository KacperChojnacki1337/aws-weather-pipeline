# AWS Weather Data Pipeline

An automated data pipeline that fetches weather information for 18 major Polish cities and stores it in a partitioned S3 Data Lake. This project demonstrates a production-ready **Bronze Layer** of a Data Lakehouse architecture.

## 🏗 Architecture
The project follows the **Medallion Architecture** (Bronze, Silver, Gold).

- **Bronze Layer (Completed):** Raw JSON data ingestion from Open-Meteo API.
- **Silver Layer (Upcoming):** Data cleaning and conversion to Apache Parquet.
- **Gold Layer (Upcoming):** Analytical views and visualizations.



## 🛠 Tech Stack
- **Cloud:** AWS (Lambda, S3, EventBridge, IAM, CloudWatch)
- **IaC:** Terraform
- **Language:** Python 3.12
- **CI/CD:** GitHub Actions

## 📂 Project Structure
- `/lambda`: Python source code for data ingestion.
- `/terraform`: Infrastructure as Code files (main.tf, variables.tf).
- `.github/workflows`: Automated deployment pipelines.

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