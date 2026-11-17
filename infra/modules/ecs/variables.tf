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

variable "image_tag" {
  description = "Tag de las imágenes a desplegar: el SHA del commit que publicó el pipeline."
  type        = string
}

variable "services" {
  description = <<-EOT
    Definición de cada microservicio. La clave es el nombre del servicio en ECS y en Cloud Map.
    image = URL del repositorio de la imagen, sin tag (el tag es image_tag); path y extra_paths = rutas
    del ALB que recibe un servicio público; environment = variables en claro; secrets = nombre de
    variable → ARN del secreto en Secrets Manager; db_init = true si el servicio usa Postgres y debe
    esperar al contenedor db-init.
  EOT
  type = map(object({
    image       = string
    cpu         = number
    memory      = number
    desired     = number
    public      = bool
    path        = optional(string, "/")
    extra_paths = optional(list(string), [])
    environment = optional(map(string), {})
    secrets     = optional(map(string), {})
    db_init     = optional(bool, false)
  }))

  validation {
    condition = alltrue(flatten([
      for s in var.services : [for arn in values(s.secrets) : startswith(arn, "arn:aws:secretsmanager:")]
    ]))
    error_message = "Cada secreto debe ser el ARN de un secreto de Secrets Manager: no se admiten valores vacíos ni en claro."
  }
}

variable "db_init" {
  description = <<-EOT
    Inicialización de las bases: imagen con psql, script SQL idempotente, variables PG* de conexión y
    el secreto PGPASSWORD. null si ningún servicio usa Postgres.
  EOT
  type = object({
    image       = string
    sql         = string
    environment = map(string)
    secrets     = map(string)
  })
  default = null
}

variable "iam_role_arn" {
  description = "Rol existente para ejecución y tarea (LabRole en AWS Academy). null = el módulo crea roles propios con permisos mínimos."
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "Certificado de ACM para el listener HTTPS del ALB. null = solo HTTP en el puerto 80."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Días de retención de logs en CloudWatch."
  type        = number
  default     = 14
}
