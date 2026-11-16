variable "name_prefix" {
  description = "Prefijo de los repositorios (ej: tero)."
  type        = string
}

variable "services" {
  description = "Lista de servicios; se crea un repositorio por cada uno."
  type        = list(string)
}
