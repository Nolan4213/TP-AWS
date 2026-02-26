variable "profile" {
  description = "AWS CLI profile"
  default     = "training"
}

variable "region" {
  description = "AWS region"
  default     = "eu-west-3"
}

variable "vpc_id" {
  description = "ID du VPC TP3"
  default     = "vpc-081cb4f820f7e2c22"
}

variable "subnet_priv_a" {
  description = "Subnet privé eu-west-3a"
  default     = "subnet-06a2e1634b5a61540"
}

variable "subnet_priv_b" {
  description = "Subnet privé eu-west-3b"
  default     = "subnet-03ea0b0c3df7883a0"
}

variable "sg_app_id" {
  description = "SG de l'instance tp4-app"
  default     = "sg-0259f1245c37aa816"
}

variable "db_username" {
  description = "Nom d'utilisateur RDS"
  default     = "admintp7"
}

variable "db_password" {
  description = "Mot de passe RDS"
  sensitive   = true
}
