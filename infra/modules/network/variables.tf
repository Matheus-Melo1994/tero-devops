variable "name_prefix" {
  description = "Prefijo para nombrar recursos (ej: tero-dev)."
  type        = string
}

variable "vpc_cidr" {
  description = "Rango CIDR de la VPC."
  type        = string
}

variable "availability_zones" {
  description = "Zonas de disponibilidad; se crea una subnet pública y una privada por zona."
  type        = list(string)
}
