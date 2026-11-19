variable "name_prefix" {
  description = "Prefijo para nombrar recursos (ej: tero-dev)."
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, test, prod): dimensión de las métricas del chequeo sintético."
  type        = string
}

variable "aws_region" {
  description = "Región de las métricas que muestra el dashboard."
  type        = string
}

variable "alb_url" {
  description = "URL pública del ALB que recorre el chequeo sintético (http:// o https://)."
  type        = string
}

variable "alb_arn_suffix" {
  description = "Dimensión LoadBalancer de las métricas del ALB."
  type        = string
}

variable "target_groups" {
  description = "Por servicio, dimensiones LoadBalancer y TargetGroup de su target group (ALB público o interno)."
  type = map(object({
    load_balancer = string
    target_group  = string
  }))
}

variable "cluster_name" {
  description = "Cluster ECS de los servicios."
  type        = string
}

variable "service_names" {
  description = "Servicios ECS por microservicio."
  type        = map(string)
}

variable "log_group_names" {
  description = "Log groups de CloudWatch por microservicio (logs JSON con el campo level)."
  type        = map(string)
}

variable "db_instance_identifier" {
  description = "Instancia RDS de PostgreSQL."
  type        = string
}

variable "redis_cache_cluster_id" {
  description = "Nodo de ElastiCache de Redis."
  type        = string
}

variable "iam_role_arn" {
  description = "Rol existente para la Lambda (LabRole en AWS Academy). null = se crea un rol con permisos mínimos."
  type        = string
  default     = null
}

variable "alarm_email" {
  description = "Correo que recibe las alarmas (la suscripción hay que confirmarla desde el correo). null = sin suscripción."
  type        = string
  default     = null
}

variable "synthetic_schedule" {
  description = "Frecuencia del chequeo sintético (expresión de EventBridge)."
  type        = string
  default     = "rate(5 minutes)"
}

variable "alb_5xx_threshold" {
  description = "Respuestas 5xx de los servicios en 5 minutos que disparan la alarma."
  type        = number
  default     = 5
}

variable "error_log_threshold" {
  description = "Líneas de log con level=error (los seis servicios juntos) en 5 minutos que disparan la alarma."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "Días de retención del log de la Lambda."
  type        = number
  default     = 14
}
