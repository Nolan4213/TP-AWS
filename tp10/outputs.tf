output "api_endpoint" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "queue_url" {
  value = aws_sqs_queue.main.url
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "validator_name" {
  value = aws_lambda_function.validator.function_name
}

output "consumer_name" {
  value = aws_lambda_function.consumer.function_name
}
