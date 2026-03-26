variable "aws_region" {
  default = "eu-west-3"
}

variable "vpc_id" {
  description = "VPC ID (TP3/TP13)"
  type        = string
}

variable "public_subnets" {
  description = "Subnets publics pour l'ALB"
  type        = list(string)
}

variable "private_subnets" {
  description = "Subnets privés pour Fargate"
  type        = list(string)
}

variable "project_name" {
  default = "tp14"
}

variable "owner" {
  default = "tp-session"
}

variable "env" {
  default = "training"
}

variable "cost_center" {
  default = "formation-aws"
}
