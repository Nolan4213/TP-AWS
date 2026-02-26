variable "profile" {
  description = "AWS CLI Profile"
  default = "training"
}

variable "region" {
  description = "AWS region"
  default = "eu-west-3"
}

variable "account_id" {
  description = "AWS Account ID"
}

variable "bucket_name" {
  description = "Nom unique du bucket S3 (global AWS)"
}