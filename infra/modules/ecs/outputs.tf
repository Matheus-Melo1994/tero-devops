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

output "target_groups" {
  description = "Dimensiones LoadBalancer y TargetGroup de las métricas de cada servicio detrás de un ALB (público o interno)."
  value = merge(
    { for k, tg in aws_lb_target_group.public : k => { load_balancer = aws_lb.this.arn_suffix, target_group = tg.arn_suffix } },
    { for k, tg in aws_lb_target_group.internal : k => { load_balancer = aws_lb.internal.arn_suffix, target_group = tg.arn_suffix } },
  )
}

output "internal_url" {
  description = "URL del ALB interno por el que se llaman los servicios."
  value       = local.internal_url
}
