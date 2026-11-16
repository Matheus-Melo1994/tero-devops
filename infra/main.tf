# Raíz: compone los módulos. Cada módulo es reutilizable entre ambientes (punto 7.3).

locals {
  name_prefix = "${var.project}-${var.environment}"
}

module "network" {
  source = "./modules/network"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "ecr" {
  source = "./modules/ecr"

  name_prefix = var.project
  services    = var.services
}
