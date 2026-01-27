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

# 1. Unique S3 Bucket
resource "aws_s3_bucket" "weather_bucket" {
  # AWS will automatically append random characters to the end
  bucket_prefix = "portfolio-weather-data-" 
}

# 2. Package the code into a ZIP file
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# 3. IAM Role (Trust policy allowing Lambda to use AWS services)
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

# 4. Permissions (Policy) - Allow Lambda to write to S3 and create logs
resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# 4a. Allow Lambda to write logs to CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 5. Lambda Function
resource "aws_lambda_function" "weather_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "weather-fetcher-terraform"
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

# 6. Scheduling Rule Definition (Cron)
resource "aws_cloudwatch_event_rule" "weather_pipeline_hourly" {
  name                = "weather-pipeline-hourly-rule"
  description         = "Wyzwalacz Lambdy co godzine"
  schedule_expression = "rate(1 hour)" # Możesz zmienić na "cron(0 * * * ? *)" dla pełnych godzin
  is_enabled          = true
}

# 7. Connecting a rule to a specific Lambda
resource "aws_cloudwatch_event_target" "run_lambda_hourly" {
  rule      = aws_cloudwatch_event_rule.weather_pipeline_hourly.name
  target_id = "TriggerWeatherLambda"
  arn       = aws_lambda_function.weather_lambda.arn # Upewnij się, że nazwa zasobu pasuje do Twojej definicji
}

# 8. Permission for EventBridge to "knock" on Lambda
resource "aws_lambda_permission" "allow_cloudwatch_to_call_weather_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weather_pipeline_hourly.arn
}

# 9. Layer with Pandas and PyArrow (for eu-north-1 region, Python 3.12)
# This ARN is available for the Stockholm region
variable "pandas_layer_arn" {
  default = "arn:aws:lambda:eu-north-1:336392948345:layer:AWSSDKPandas-Python312:13"
}


# 10. New Lambda function for Silver layer
resource "aws_lambda_function" "weather_transformer" {
  filename         = data.archive_file.lambda_zip.output_path 
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "weather-transformer-silver"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "transformer.lambda_handler" 
  runtime          = "python3.12"
  timeout          = 60 # 
  memory_size      = 256 # 

  layers = [var.pandas_layer_arn]

  environment {
    variables = {
      MY_DATA_BUCKET = aws_s3_bucket.weather_bucket.id
    }
  }
}
# 11. Permission for S3 to run Lambda Transformer
resource "aws_lambda_permission" "allow_s3_to_call_transformer" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_transformer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.weather_bucket.arn
}

# S3 Notification Configuration
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.weather_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.weather_transformer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/" 
  }

  depends_on = [aws_lambda_permission.allow_s3_to_call_transformer]
}


