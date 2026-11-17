output "cluster_name" {
  description = "Nombre del cluster ECS; lo usa el pipeline para desplegar."
  value       = aws_ecs_cluster.this.name
}

output "alb_dns_name" {
  description = "URL pública de la tienda (ui en /, admin en /admin)."
  value       = aws_lb.this.dns_name
}

output "service_names" {
  description = "Nombres de los servicios ECS, indexados por microservicio."
  value       = { for k, s in aws_ecs_service.this : k => s.name }
}

output "log_group_names" {
  description = "Log groups de CloudWatch por servicio; base del dashboard y las alertas."
  value       = { for k, g in aws_cloudwatch_log_group.this : k => g.name }
}

output "alb_arn_suffix" {
  description = "Sufijo del ARN del ALB, dimensión LoadBalancer de sus métricas en CloudWatch."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffixes" {
  description = "Sufijo del ARN de cada target group público, dimensión TargetGroup de sus métricas."
  value       = { for k, tg in aws_lb_target_group.public : k => tg.arn_suffix }
}

output "namespace" {
  description = "Namespace privado de descubrimiento (ej: dev.tero.local)."
  value       = aws_service_discovery_private_dns_namespace.this.name
}
