output "kms_key_id" {
  value = aws_kms_key.tp12.key_id
}

output "kms_key_arn" {
  value = aws_kms_key.tp12.arn
}

output "kms_alias" {
  value = aws_kms_alias.tp12.name
}

output "secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "secret_name" {
  value = aws_secretsmanager_secret.db_credentials.name
}

output "guardduty_detector_id" {
  value = aws_guardduty_detector.tp12.id
}
