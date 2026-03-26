variable "aws_region" {
  description = "Région AWS"
  type        = string
  default     = "eu-west-3"
}

variable "profile" {
  description = "Profil AWS CLI"
  type        = string
}

variable "account_id" {
  description = "ID du compte AWS"
  type        = string
}

variable "dynamodb_table" {
  description = "Nom de la table DynamoDB TP8"
  type        = string
  default     = "tp8-orders"
}
