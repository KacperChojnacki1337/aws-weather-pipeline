# --- TERRAFORM CONFIGURATION ---
terraform {
  backend "s3" {
    bucket = "k.ch-terraform-state"
    key    = "weather-pipeline/terraform.tfstate"
    region = "eu-north-1"
  }
}

provider "aws" {
  region = "eu-north-1" # Stockholm
}

# --- INFRASTRUCTURE: STORAGE ---

# S3 Bucket for raw and transformed data
resource "aws_s3_bucket" "weather_bucket" {
  bucket_prefix = "portfolio-weather-data-" 
}

# --- INFRASTRUCTURE: COMPUTE (LAMBDA) ---

# Package the lambda directory into a ZIP file
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# Execution Role for Lambda functions
resource "aws_iam_role" "lambda_exec_role" {
  name = "weather_pipeline_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Attach Full S3 Access to Lambda Role
resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Attach Basic Execution Role (CloudWatch Logs) to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Bronze Lambda: Fetches data from API and saves to S3
resource "aws_lambda_function" "weather_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "weather-fetcher-bronze"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      MY_DATA_BUCKET = aws_s3_bucket.weather_bucket.id
    }
  }
}

# Silver Lambda: Transforms JSON to Parquet (Flattening)
resource "aws_lambda_function" "weather_transformer" {
  filename         = data.archive_file.lambda_zip.output_path 
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "weather-transformer-silver"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "transformer.lambda_handler" 
  runtime          = "python3.12"
  timeout          = 60 
  memory_size      = 512 

  layers = ["arn:aws:lambda:eu-north-1:336392948345:layer:AWSSDKPandas-Python312:13"]

  environment {
    variables = {
      MY_DATA_BUCKET = aws_s3_bucket.weather_bucket.id
    }
  }
}

# --- TRIGGERS & PERMISSIONS ---

# EventBridge Rule: Trigger Bronze Lambda every hour
resource "aws_cloudwatch_event_rule" "weather_pipeline_hourly" {
  name                = "weather-pipeline-hourly-rule"
  description         = "Triggers Lambda hourly"
  schedule_expression = "rate(1 hour)"
  state         = "ENABLED"
}

resource "aws_cloudwatch_event_target" "run_lambda_hourly" {
  rule      = aws_cloudwatch_event_rule.weather_pipeline_hourly.name
  target_id = "TriggerWeatherLambda"
  arn       = aws_lambda_function.weather_lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_weather_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weather_pipeline_hourly.arn
}

# S3 Notification: Trigger Silver Lambda when new JSON appears in raw/
resource "aws_lambda_permission" "allow_s3_to_call_transformer" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_transformer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.weather_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.weather_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.weather_transformer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/" 
  }

  depends_on = [aws_lambda_permission.allow_s3_to_call_transformer]
}

# --- GOLD LAYER: DATA CATALOG & CRAWLER ---

# IAM Role for AWS Glue Crawler
resource "aws_iam_role" "glue_crawler_role" {
  name = "weather_glue_crawler_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

# Standard AWS Glue Service Policy
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom policy for Glue to read the S3 bucket
resource "aws_iam_role_policy" "glue_s3_access" {
  name = "glue_s3_read_access"
  role = aws_iam_role.glue_crawler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Effect   = "Allow"
      Resource = [
        "arn:aws:s3:::${aws_s3_bucket.weather_bucket.bucket}",
        "arn:aws:s3:::${aws_s3_bucket.weather_bucket.bucket}/*"
      ]
    }]
  })
}

# Glue Database
resource "aws_glue_catalog_database" "weather_db" {
  name = "weather_data_db"
}

# Glue Crawler to catalog transformed Parquet data
resource "aws_glue_crawler" "weather_crawler" {
  database_name = aws_glue_catalog_database.weather_db.name
  name          = "weather_silver_crawler"
  role          = aws_iam_role.glue_crawler_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.weather_bucket.bucket}/transformed/"
  }
}

# --- SECURITY: IAM USER FOR DEVELOPER ---

resource "aws_iam_user" "kch_dev" {
  name = "KCH-DEV"
  tags = { Project = "WeatherPortfolio" }
}

resource "aws_iam_user_policy_attachment" "kch_dev_admin" {
  user       = aws_iam_user.kch_dev.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_access_key" "kch_dev_keys" {
  user = aws_iam_user.kch_dev.name
}

# --- OUTPUTS ---

output "kch_dev_access_key_id" {
  value = aws_iam_access_key.kch_dev_keys.id
}

output "kch_dev_secret_access_key" {
  value     = aws_iam_access_key.kch_dev_keys.secret
  sensitive = true
}