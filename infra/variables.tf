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
