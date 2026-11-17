variable "name_prefix" {
  description = "Prefijo para nombrar recursos (ej: tero-dev)."
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, test, prod)."
  type        = string
}

variable "aws_region" {
  description = "Región, usada por el driver awslogs."
  type        = string
}

variable "vpc_id" {
  description = "VPC donde se despliega el cluster."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets públicas para el ALB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Subnets privadas para las tareas ECS."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group del ALB (del módulo network)."
  type        = string
}

variable "services_security_group_id" {
  description = "Security group de los servicios (del módulo network)."
  type        = string
}

variable "image_registry" {
  description = "Prefijo del registry de imágenes, ej: ghcr.io/matheus-melo1994 o <cuenta>.dkr.ecr.us-east-1.amazonaws.com."
  type        = string
}

variable "image_tag" {
  description = "Tag de las imágenes a desplegar (SHA del commit o latest)."
  type        = string
  default     = "latest"
}

variable "services" {
  description = <<-EOT
    Definición de cada microservicio. environment = variables en claro; secrets = nombre de variable → ARN del secreto
    en Secrets Manager (vacío hasta que exista el módulo data).
  EOT
  type = map(object({
    cpu         = number
    memory      = number
    desired     = number
    public      = bool
    path        = optional(string, "/")
    environment = optional(map(string), {})
    secrets     = optional(map(string), {})
  }))
}

variable "log_retention_days" {
  description = "Días de retención de logs en CloudWatch."
  type        = number
  default     = 14
}
