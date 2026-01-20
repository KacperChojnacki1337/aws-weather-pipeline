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

# 5. Lambda Function
resource "aws_lambda_function" "weather_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  function_name    = "weather-fetcher-terraform"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"

  environment {
    variables = {
      MY_DATA_BUCKET = aws_s3_bucket.weather_bucket.id
    }
  }
}