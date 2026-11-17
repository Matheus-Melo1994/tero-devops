# Outputs raíz con descripción (punto 7.5). Los consume el pipeline de deploy.

output "vpc_id" {
  description = "ID de la VPC del ambiente."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Subnets públicas (para el ALB)."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Subnets privadas (para ECS, RDS y Redis)."
  value       = module.network.private_subnet_ids
}

output "ecr_repository_urls" {
  description = "URL de cada repositorio ECR, por servicio. El pipeline hace push acá."
  value       = local.ecr_repository_urls
}

output "alb_url" {
  description = "URL pública de la tienda en este ambiente."
  value       = "${var.certificate_arn == null ? "http" : "https"}://${module.ecs.alb_dns_name}"
}

output "ecs_cluster_name" {
  description = "Nombre del cluster ECS; lo usa el pipeline de deploy."
  value       = module.ecs.cluster_name
}

output "ecs_service_names" {
  description = "Servicios ECS por microservicio; los usa el pipeline de deploy."
  value       = module.ecs.service_names
}

output "log_group_names" {
  description = "Log groups de CloudWatch por servicio."
  value       = module.ecs.log_group_names
}

output "db_host" {
  description = "Endpoint de PostgreSQL (solo alcanzable desde las subnets privadas)."
  value       = module.data.db_host
}

output "redis_url" {
  description = "URL de Redis que usa checkout."
  value       = module.data.redis_url
}

output "secret_arns" {
  description = "ARN de los secretos del ambiente. El valor se lee con: aws secretsmanager get-secret-value --secret-id <arn>."
  value = {
    db_password      = module.data.db_password_secret_arn
    admin_password   = module.data.admin_password_secret_arn
    admin_jwt_secret = module.data.admin_jwt_secret_arn
  }
}
