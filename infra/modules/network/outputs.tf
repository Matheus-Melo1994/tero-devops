output "vpc_id" {
  description = "ID de la VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs de las subnets públicas."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas."
  value       = aws_subnet.private[*].id
}

output "alb_security_group_id" {
  description = "Security group del ALB."
  value       = aws_security_group.alb.id
}

output "services_security_group_id" {
  description = "Security group de los servicios ECS."
  value       = aws_security_group.services.id
}

output "data_security_group_id" {
  description = "Security group de Postgres y Redis."
  value       = aws_security_group.data.id
}
