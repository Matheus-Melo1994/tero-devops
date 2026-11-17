# Variables raíz. Los valores por ambiente están en environments/<env>.tfvars.

variable "project" {
  description = "Nombre del proyecto, usado como prefijo de recursos."
  type        = string
  default     = "tero"
}

variable "environment" {
  description = "Ambiente a desplegar: dev, test o prod."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment debe ser dev, test o prod."
  }
}

variable "aws_region" {
  description = "Región de AWS donde se despliega."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "Rango CIDR de la VPC."
  type        = string
}

variable "availability_zones" {
  description = "Zonas de disponibilidad a usar (mínimo 2 para el ALB)."
  type        = list(string)
}

variable "services" {
  description = "Nombres de los microservicios de Tero; un repositorio ECR por cada uno."
  type        = list(string)
  default     = ["catalog", "orders", "ui", "admin", "checkout", "cart"]
}

# ---------- Agregar al final de infra/variables.tf ----------

variable "image_registry" {
  description = "Registry de donde ECS baja las imágenes. GHCR mientras no se use ECR."
  type        = string
  default     = "ghcr.io/matheus-melo1994"
}

variable "image_tag" {
  description = "Tag a desplegar; el pipeline pasa el SHA del commit."
  type        = string
  default     = "latest"
}

variable "desired_count" {
  description = "Réplicas por servicio."
  type        = number
  default     = 1
}

variable "db_host" {
  description = "Host de PostgreSQL. Lo provee el módulo data; hasta entonces, placeholder."
  type        = string
  default     = "db.placeholder"
}

variable "redis_host" {
  description = "Host de Redis. Lo provee el módulo data; hasta entonces, placeholder."
  type        = string
  default     = "redis.placeholder"
}

variable "db_password_arn" {
  description = "ARN del secreto de la contraseña de Postgres en Secrets Manager. Vacío hasta el módulo data."
  type        = string
  default     = ""
}

variable "admin_password_arn" {
  description = "ARN del secreto ADMIN_PASSWORD. Vacío hasta el módulo data."
  type        = string
  default     = ""
}

variable "admin_jwt_secret_arn" {
  description = "ARN del secreto ADMIN_JWT_SECRET. Vacío hasta el módulo data."
  type        = string
  default     = ""
}
