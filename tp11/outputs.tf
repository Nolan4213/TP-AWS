output "dashboard_url" {
  value = "https://eu-west-3.console.aws.amazon.com/cloudwatch/home?region=eu-west-3#dashboards:name=tp11-pipeline-observability"
}

output "alarm_dlq" {
  value = aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_name
}

output "alarm_lambda_errors" {
  value = aws_cloudwatch_metric_alarm.lambda_consumer_errors.alarm_name
}

output "alarm_apigw_5xx" {
  value = aws_cloudwatch_metric_alarm.apigw_5xx.alarm_name
}

output "cloudtrail_name" {
  value = aws_cloudtrail.tp11.name
}

output "cloudtrail_bucket" {
  value = aws_s3_bucket.cloudtrail.id
}
