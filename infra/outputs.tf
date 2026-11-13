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
