variable "aws_region" {
  description = "Région AWS"
  type        = string
  default     = "eu-west-3"
}

variable "profile" {
  description = "Profil AWS CLI"
  type        = string
}

variable "bucket_name" {
  description = "Nom du bucket S3 TP6"
  type        = string
}

variable "account_id" {
  description = "ID du compte AWS"
  type        = string
}
