provider "aws" {
  region  = var.aws_region
  profile = var.profile
}

# --- SQS Queue principale ---
resource "aws_sqs_queue" "main" {
  name                       = "tp10-queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

# --- DLQ ---
resource "aws_sqs_queue" "dlq" {
  name                      = "tp10-dlq"
  message_retention_seconds = 86400
}

# --- IAM Role Lambda Validator ---
resource "aws_iam_role" "validator_role" {
  name = "tp10-validator-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "validator_policy" {
  name = "tp10-validator-policy"
  role = aws_iam_role.validator_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.main.arn
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/lambda/tp10-validator:*"
      }
    ]
  })
}

# --- IAM Role Lambda Consumer ---
resource "aws_iam_role" "consumer_role" {
  name = "tp10-consumer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "consumer_policy" {
  name = "tp10-consumer-policy"
  role = aws_iam_role.consumer_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.main.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.dynamodb_table}"
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/lambda/tp10-consumer:*"
      }
    ]
  })
}

# --- ZIP Lambda Validator ---
data "archive_file" "validator_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/validator.py"
  output_path = "${path.module}/lambda/validator.zip"
}

# --- ZIP Lambda Consumer ---
data "archive_file" "consumer_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/consumer.py"
  output_path = "${path.module}/lambda/consumer.zip"
}

# --- Lambda Validator ---
resource "aws_lambda_function" "validator" {
  function_name    = "tp10-validator"
  role             = aws_iam_role.validator_role.arn
  handler          = "validator.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.validator_zip.output_path
  source_code_hash = data.archive_file.validator_zip.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      SQS_QUEUE_URL = aws_sqs_queue.main.url
    }
  }
}

# --- Lambda Consumer ---
resource "aws_lambda_function" "consumer" {
  function_name    = "tp10-consumer"
  role             = aws_iam_role.consumer_role.arn
  handler          = "consumer.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.consumer_zip.output_path
  source_code_hash = data.archive_file.consumer_zip.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table
      FORCE_ERROR    = "false"
    }
  }
}

# --- CloudWatch Log Groups ---
resource "aws_cloudwatch_log_group" "validator_logs" {
  name              = "/aws/lambda/tp10-validator"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "consumer_logs" {
  name              = "/aws/lambda/tp10-consumer"
  retention_in_days = 7
}

# --- Trigger SQS → Lambda Consumer ---
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 1
  enabled          = true
}

# --- API Gateway HTTP ---
resource "aws_apigatewayv2_api" "api" {
  name          = "tp10-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "validator" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.validator.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_items" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /items"
  target    = "integrations/${aws_apigatewayv2_integration.validator.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
