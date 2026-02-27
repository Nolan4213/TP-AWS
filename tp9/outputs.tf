output "lambda_name" {
  value = aws_lambda_function.s3_validator.function_name
}

output "lambda_arn" {
  value = aws_lambda_function.s3_validator.arn
}

output "log_group" {
  value = aws_cloudwatch_log_group.lambda_logs.name
}
