output "repository_urls" {
  description = "URL de cada repositorio, indexado por servicio."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" {
  description = "ARN de cada repositorio, indexado por servicio."
  value       = { for k, r in aws_ecr_repository.this : k => r.arn }
}
