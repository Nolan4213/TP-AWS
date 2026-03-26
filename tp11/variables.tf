variable "aws_region" {
  default = "eu-west-3"
}

variable "consumer_function_name" {
  default = "tp10-consumer"
}

variable "validator_function_name" {
  default = "tp10-validator"
}

variable "sqs_queue_name" {
  default = "tp10-queue"
}

variable "dlq_name" {
  default = "tp10-dlq"
}

variable "api_id" {
  description = "ID de l'API Gateway TP10 (ex: mlt152umse)"
  default     = "mlt152umse"
}

variable "alarm_sns_arn" {
  description = "ARN SNS pour les alarmes (laisser vide si non configuré)"
  default     = ""
}
