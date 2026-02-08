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

# --- 1. STORAGE (S3) ---

# Main S3 Bucket for the Data Lake
resource "aws_s3_bucket" "weather_bucket" {
  bucket_prefix = "portfolio-weather-data-"
}

# STEP 4: Lifecycle Management (Professional Cost Optimization)
resource "aws_s3_bucket_lifecycle_configuration" "weather_bucket_lifecycle" {
  bucket = aws_s3_bucket.weather_bucket.id

  rule {
    id     = "archive_old_raw_data"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    # Transition to cheaper storage after 30 days, expire after 90
    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }

    expiration {
      days = 90
    }
  }
}

# --- 2. COMPUTE (LAMBDA) ---

# Package the local lambda directory into a deployment ZIP
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# Unified IAM Role for Lambda execution
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

# Grant Lambdas access to S3
resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Grant Lambdas permission to write CloudWatch logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Bronze Lambda: Ingests data from API to S3
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

# Silver Lambda: Processes JSON into Parquet (Schema Enforcement & Cleaning)
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

# --- 3. TRIGGERS & PERMISSIONS ---

# EventBridge Rule: Trigger Bronze Lambda every hour
resource "aws_cloudwatch_event_rule" "weather_pipeline_hourly" {
  name                = "weather-pipeline-hourly-rule"
  schedule_expression = "rate(1 hour)"
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "run_lambda_hourly" {
  rule      = aws_cloudwatch_event_rule.weather_pipeline_hourly.name
  target_id = "TriggerWeatherLambda"
  arn       = aws_lambda_function.weather_lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weather_pipeline_hourly.arn
}

# S3 Event: Trigger Silver Lambda when new objects are created in raw/
resource "aws_lambda_permission" "allow_s3" {
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
  depends_on = [aws_lambda_permission.allow_s3]
}

# --- 4. DATA CATALOGING (GLUE) ---

# IAM Role for Glue Crawler
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

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_access" {
  name = "glue_s3_read_access"
  role = aws_iam_role.glue_crawler_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Effect   = "Allow"
      Resource = ["${aws_s3_bucket.weather_bucket.arn}", "${aws_s3_bucket.weather_bucket.arn}/*"]
    }]
  })
}

# Glue Database to store table metadata
resource "aws_glue_catalog_database" "weather_db" {
  name = "weather_data_db"
}

# Glue Crawler to automatically discover schema in the Silver layer
resource "aws_glue_crawler" "weather_crawler" {
  database_name = aws_glue_catalog_database.weather_db.name
  name          = "weather_silver_crawler"
  role          = aws_iam_role.glue_crawler_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.weather_bucket.bucket}/transformed/"
  }
}

# --- 5. MONITORING & ALERTING (SNS & CLOUDWATCH) ---

# SNS Topic for error notifications
resource "aws_sns_topic" "lambda_error_alerts" {
  name = "weather-pipeline-error-alerts"
}

# Email subscription (Confirmation email must be clicked!)
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.lambda_error_alerts.arn
  protocol  = "email"
  endpoint  = "kmchojnacki17@gmail.com"} # 

# CloudWatch Alarm to monitor Silver Lambda execution failures
resource "aws_cloudwatch_metric_alarm" "silver_lambda_errors" {
  alarm_name          = "weather-silver-transformer-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300" # 5-minute window
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Critical: Silver Lambda transformation failed."
  
  dimensions = {
    FunctionName = aws_lambda_function.weather_transformer.function_name
  }

  alarm_actions = [aws_sns_topic.lambda_error_alerts.arn]
}

# --- 6. DEVELOPER ACCESS ---

resource "aws_iam_user" "kch_dev" {
  name = "KCH-DEV"
}

resource "aws_iam_user_policy_attachment" "kch_dev_admin" {
  user       = aws_iam_user.kch_dev.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_access_key" "kch_dev_keys" {
  user = aws_iam_user.kch_dev.name
}

# --- 7. OUTPUTS ---

output "kch_dev_access_key_id" {
  value = aws_iam_access_key.kch_dev_keys.id
}

output "kch_dev_secret_access_key" {
  value     = aws_iam_access_key.kch_dev_keys.secret
  sensitive = true
}

output "s3_bucket_name" {
  value = aws_s3_bucket.weather_bucket.id
}