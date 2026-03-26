terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "training"
}

# ─── Data sources ───────────────────────────────────────────────
data "aws_caller_identity" "current" {}

data "aws_sqs_queue" "dlq" {
  name = var.dlq_name
}

data "aws_sqs_queue" "queue" {
  name = var.sqs_queue_name
}

# ─── CloudWatch Dashboard ────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "tp11" {
  dashboard_name = "tp11-pipeline-observability"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "## TP10 Pipeline — Observabilité : Erreurs · Latence · DLQ · Saturation"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "Lambda consumer — Erreurs"
          region  = "eu-west-3"
          view    = "timeSeries"
          stat    = "Sum"
          period  = 60
          metrics = [["AWS/Lambda", "Errors", "FunctionName", var.consumer_function_name]]
          annotations = { horizontal = [] }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "Lambda — Durée (ms)"
          region  = "eu-west-3"
          view    = "timeSeries"
          stat    = "Average"
          period  = 60
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.consumer_function_name],
            ["AWS/Lambda", "Duration", "FunctionName", var.validator_function_name]
          ]
          annotations = { horizontal = [] }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title   = "DLQ — Messages visibles"
          region  = "eu-west-3"
          view    = "timeSeries"
          stat    = "Maximum"
          period  = 60
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.dlq_name]]
          annotations = { horizontal = [] }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 8
        height = 6
        properties = {
          title   = "API Gateway — 5xx"
          region  = "eu-west-3"
          view    = "timeSeries"
          stat    = "Sum"
          period  = 60
          metrics = [["AWS/ApiGateway", "5XXError", "ApiId", var.api_id]]
          annotations = { horizontal = [] }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 7
        width  = 8
        height = 6
        properties = {
          title   = "API Gateway — Latence p99 (ms)"
          region  = "eu-west-3"
          view    = "timeSeries"
          stat    = "p99"
          period  = 60
          metrics = [["AWS/ApiGateway", "Latency", "ApiId", var.api_id]]
          annotations = { horizontal = [] }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 7
        width  = 8
        height = 6
        properties = {
          title   = "SQS queue — Messages en attente"
          region  = "eu-west-3"
          view    = "timeSeries"
          stat    = "Maximum"
          period  = 60
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.sqs_queue_name]]
          annotations = { horizontal = [] }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 8
        height = 6
        properties = {
          title   = "Lambda — Throttles"
          region  = "eu-west-3"
          view    = "timeSeries"
          stat    = "Sum"
          period  = 60
          metrics = [
            ["AWS/Lambda", "Throttles", "FunctionName", var.consumer_function_name],
            ["AWS/Lambda", "Throttles", "FunctionName", var.validator_function_name]
          ]
          annotations = { horizontal = [] }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 13
        width  = 8
        height = 6
        properties = {
          title   = "Lambda — Invocations"
          region  = "eu-west-3"
          view    = "timeSeries"
          stat    = "Sum"
          period  = 60
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.consumer_function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", var.validator_function_name]
          ]
          annotations = { horizontal = [] }
        }
      }
    ]
  })
}


# ─── Alarmes CloudWatch ──────────────────────────────────────────

# Alarme 1 : DLQ non vide
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "tp11-alarm-dlq-not-empty"
  alarm_description   = "La DLQ tp10 contient des messages — consumer en échec"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.dlq_name
  }

  alarm_actions = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []
  ok_actions    = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []

  tags = {
    Project = "TP11"
    Env     = "training"
  }
}

# Alarme 2 : Erreurs Lambda consumer
resource "aws_cloudwatch_metric_alarm" "lambda_consumer_errors" {
  alarm_name          = "tp11-alarm-lambda-consumer-errors"
  alarm_description   = "Le consumer Lambda lève des erreurs — traitement SQS en échec"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.consumer_function_name
  }

  alarm_actions = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []

  tags = {
    Project = "TP11"
    Env     = "training"
  }
}

# Alarme 3 : API Gateway 5xx
resource "aws_cloudwatch_metric_alarm" "apigw_5xx" {
  alarm_name          = "tp11-alarm-apigw-5xx"
  alarm_description   = "L'API Gateway retourne des 5xx — validator Lambda en erreur"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = var.api_id
  }

  alarm_actions = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []

  tags = {
    Project = "TP11"
    Env     = "training"
  }
}

# Alarme 4 : Lambda throttles
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "tp11-alarm-lambda-throttles"
  alarm_description   = "Throttling détecté sur les Lambdas TP10 — saturation concurrence"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.consumer_function_name
  }

  alarm_actions = var.alarm_sns_arn != "" ? [var.alarm_sns_arn] : []

  tags = {
    Project = "TP11"
    Env     = "training"
  }
}

# ─── CloudTrail ──────────────────────────────────────────────────
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "tp11-cloudtrail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Project = "TP11"
    Env     = "training"
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::${aws_s3_bucket.cloudtrail.id}"
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${aws_s3_bucket.cloudtrail.id}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "tp11" {
  name                          = "tp11-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = {
    Project = "TP11"
    Env     = "training"
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
