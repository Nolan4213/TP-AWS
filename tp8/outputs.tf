output "table_name" {
  value = aws_dynamodb_table.orders.name
}

output "table_arn" {
  value = aws_dynamodb_table.orders.arn
}

output "stream_arn" {
  value = aws_dynamodb_table.orders.stream_arn
}

output "gsi_name" {
  value = "status-index"
}
