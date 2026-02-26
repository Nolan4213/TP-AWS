output "bucket_name" {
  description = "Nom du bucket S3"
  value       = aws_s3_bucket.tp6.id
}

output "bucket_arn" {
  description = "ARN du bucket S3"
  value       = aws_s3_bucket.tp6.arn
}

output "versioning_status" {
  description = "Statut du versioning"
  value       = aws_s3_bucket_versioning.tp6.versioning_configuration[0].status
}
