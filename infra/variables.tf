# Variables raíz. Los valores por ambiente están en environments/<env>.tfvars.
# Ninguna lleva secretos: las contraseñas las genera el módulo data y quedan en Secrets Manager.

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

# ---------- Recursos de la cuenta y permisos ----------
variable "manage_shared_resources" {
  description = <<-EOT
    true en un solo ambiente por cuenta (Dev): su estado crea y administra los recursos que comparten los
    tres ambientes (los repositorios ECR). false = solo los lee.
  EOT
  type        = bool
  default     = false
}

variable "existing_iam_role_name" {
  description = <<-EOT
    Rol IAM existente para ECS y Lambda. En AWS Academy (Learner Lab) no se pueden crear roles y se usa
    LabRole. null = Terraform crea roles propios con permisos mínimos.
  EOT
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "Certificado de ACM para servir HTTPS en el ALB (80 redirige a 443). null = solo HTTP."
  type        = string
  default     = null
}

variable "services" {
  description = "Nombres de los microservicios de Tero; un repositorio ECR y un servicio ECS por cada uno."
  type        = list(string)
  default     = ["catalog", "orders", "ui", "admin", "checkout", "cart"]
}

# ---------- Imágenes ----------
variable "image_tag" {
  description = "SHA del commit cuyas imágenes se despliegan (tero-<servicio>:<sha> en ECR). El pipeline lo pasa con -var."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.image_tag))
    error_message = "image_tag debe ser el SHA completo del commit (40 caracteres hexadecimales); no se despliega latest."
  }
}

variable "db_init_image" {
  description = "Imagen con psql que ejecuta la inicialización de las bases (misma versión mayor que RDS)."
  type        = string
  default     = "public.ecr.aws/docker/library/postgres:16-alpine"
}

variable "desired_count" {
  description = "Réplicas por servicio."
  type        = number
  default     = 1
}

# ---------- Datos ----------
variable "db_instance_class" {
  description = "Clase de instancia de RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_multi_az" {
  description = "RDS con réplica en espera en otra zona (duplica el costo)."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Días de retención de los backups automáticos de RDS."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Impide borrar la base con terraform destroy."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Si es true, destroy no deja snapshot final de la base."
  type        = bool
  default     = false
}

variable "redis_node_type" {
  description = "Tipo de nodo de ElastiCache."
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_transit_encryption" {
  description = "TLS entre checkout y Redis."
  type        = bool
  default     = true
}

variable "secret_recovery_window_days" {
  description = "Días que Secrets Manager retiene un secreto borrado (0 = borrado inmediato, para ambientes que se destruyen y recrean)."
  type        = number
  default     = 7
}
