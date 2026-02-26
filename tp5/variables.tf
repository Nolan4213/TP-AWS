variable "profile" {
  default = "training"
}
variable "region" {
  default = "eu-west-3"
}
variable "vpc_id" {}
variable "pub1" {}
variable "pub2" {}
variable "priv1" {}
variable "priv2" {}
variable "ami_id" {}
variable "instance_profile" {
  default = "EC2SSMProfile"
}
variable "priv_rt" {
  description = "Route table privée ID du TP3"
}