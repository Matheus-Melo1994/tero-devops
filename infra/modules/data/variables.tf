variable "name_prefix" {
  description = "Prefijo para nombrar recursos (ej: tero-dev)."
  type        = string
}

variable "secrets_prefix" {
  description = "Prefijo de los nombres en Secrets Manager (ej: tero/dev)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas donde viven RDS y Redis (mínimo 2 zonas)."
  type        = list(string)
}

variable "data_security_group_id" {
  description = "Security group de datos (del módulo network): solo admite 5432 y 6379 desde los servicios."
  type        = string
}

# ---------- PostgreSQL ----------
variable "db_username" {
  description = "Usuario de PostgreSQL que usan los servicios (mismo que en docker-compose)."
  type        = string
  default     = "retail_user"
}

variable "db_initial_database" {
  description = "Base que crea RDS al nacer la instancia. catalogdb y cartdb las crea init-db.sql."
  type        = string
  default     = "orders"
}

variable "db_engine_version" {
  description = "Versión mayor de PostgreSQL (misma que la imagen postgres:16 de docker-compose)."
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "Clase de instancia de RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Almacenamiento de RDS en GB."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Réplica en espera en otra zona. Duplica el costo: solo para Prod."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Días de retención de los backups automáticos de RDS."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Impide borrar la instancia con terraform destroy. Activar en Prod."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Si es true, destroy no deja snapshot final (ambientes descartables)."
  type        = bool
  default     = false
}

# ---------- Redis ----------
variable "redis_engine_version" {
  description = "Versión de Redis (docker-compose usa redis:7)."
  type        = string
  default     = "7.1"
}

variable "redis_node_type" {
  description = "Tipo de nodo de ElastiCache."
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_transit_encryption" {
  description = "TLS entre checkout y Redis. Con true la URL pasa a ser rediss://."
  type        = bool
  default     = true
}

# ---------- Secretos ----------
variable "secret_recovery_window_days" {
  description = "Días que Secrets Manager retiene un secreto borrado. 0 permite destruir y recrear el ambiente sin esperar."
  type        = number
  default     = 7

  validation {
    condition     = var.secret_recovery_window_days == 0 || (var.secret_recovery_window_days >= 7 && var.secret_recovery_window_days <= 30)
    error_message = "secret_recovery_window_days debe ser 0 o estar entre 7 y 30."
  }
}
