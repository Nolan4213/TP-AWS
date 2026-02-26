output "alb_dns" {
  description = "URL publique de l'ALB"
  value       = "http://${aws_lb.tp5.dns_name}"
}

output "alb_arn" {
  value = aws_lb.tp5.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.tp5.arn
}

output "asg_name" {
  value = aws_autoscaling_group.tp5.name
}

/*output "nat_gateway_id" {
  description = "ID du NAT Gateway - a supprimer apres bootstrap"
  value       = aws_nat_gateway.tp5.id
}*/
