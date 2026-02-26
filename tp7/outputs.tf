output "rds_endpoint" {
  description = "Endpoint RDS a utiliser depuis l'instance app"
  value       = aws_db_instance.tp7.endpoint
}

output "rds_sg_id" {
  description = "ID du Security Group RDS"
  value       = aws_security_group.rds.id
}

output "db_subnet_group" {
  description = "Nom du DB Subnet Group"
  value       = aws_db_subnet_group.tp7.name
}
