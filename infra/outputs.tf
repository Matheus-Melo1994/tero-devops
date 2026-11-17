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
  value       = module.ecr.repository_urls
}

# ---------- Agregar al final de infra/outputs.tf ----------

output "alb_url" {
  description = "URL pública de la tienda en este ambiente."
  value       = "http://${module.ecs.alb_dns_name}"
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
