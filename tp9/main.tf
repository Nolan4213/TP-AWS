provider "aws" {
  region  = var.aws_region
  profile = var.profile
}

# --- IAM Role Lambda ---
resource "aws_iam_role" "lambda_role" {
  name = "tp9-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# --- IAM Policy minimale ---
resource "aws_iam_role_policy" "lambda_policy" {
  name = "tp9-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3ReadInput"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.bucket_name}/input/*"
      },
      {
        Sid      = "S3WriteOutput"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::${var.bucket_name}/output/*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/lambda/tp9-s3-validator:*"
      }
    ]
  })
}

# --- ZIP du code Lambda ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/lambda/handler.zip"
}

# --- Lambda Function ---
resource "aws_lambda_function" "s3_validator" {
  function_name    = "tp9-s3-validator"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      BUCKET_NAME = var.bucket_name
    }
  }
}

# --- CloudWatch Log Group ---
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/tp9-s3-validator"
  retention_in_days = 7
}

# --- Permission S3 → Lambda ---
resource "aws_lambda_permission" "s3_trigger" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_validator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.bucket_name}"
}

# --- Trigger S3 sur préfixe input/ ---
resource "aws_s3_bucket_notification" "trigger" {
  bucket = var.bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_validator.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
  }

  depends_on = [aws_lambda_permission.s3_trigger]
}
