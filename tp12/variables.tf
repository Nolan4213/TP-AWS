variable "aws_region" {
  default = "eu-west-3"
}

variable "account_id" {
  description = "AWS Account ID"
  default     = "792390865255"
}

variable "consumer_role_name" {
  default = "tp10-consumer-role"
}



variable "secret_username" {
  default = "admin"
}

variable "secret_password" {
  default     = "Sup3rS3cr3t!"
  sensitive   = true
}
variable "s3_bucket_name" {
  description = "Bucket S3 à chiffrer avec KMS"
  default     = "tp12-training-792390865255"
}
