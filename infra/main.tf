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

# ---------- Agregar al final de infra/main.tf ----------

locals {
  ns = "${var.environment}.tero.local"

  # Endpoints internos: cada servicio encuentra a los otros por Cloud Map, igual que en compose.
  # Las contraseñas no van acá: entran por secrets desde Secrets Manager cuando exista el módulo data.
  service_definitions = {
    ui = {
      cpu = 256, memory = 512, desired = var.desired_count, public = true, path = "/"
      environment = {
        RETAIL_UI_ENDPOINTS_CATALOG  = "http://catalog.${local.ns}:8080"
        RETAIL_UI_ENDPOINTS_CARTS    = "http://carts.${local.ns}:8080"
        RETAIL_UI_ENDPOINTS_CHECKOUT = "http://checkout.${local.ns}:8080"
        RETAIL_UI_ENDPOINTS_ORDERS   = "http://orders.${local.ns}:8080"
        PORT                         = "8080"
      }
    }
    admin = {
      cpu = 256, memory = 512, desired = var.desired_count, public = true, path = "/admin"
      environment = {
        DB_HOST        = var.db_host
        DB_PORT        = "5432"
        DB_USER        = "retail_user"
        ADMIN_USERNAME = "admin"
        PORT           = "8080"
      }
      secrets = var.db_password_arn == "" ? {} : {
        DB_PASSWORD      = var.db_password_arn
        ADMIN_PASSWORD   = var.admin_password_arn
        ADMIN_JWT_SECRET = var.admin_jwt_secret_arn
      }
    }
    catalog = {
      cpu = 256, memory = 512, desired = var.desired_count, public = false
      environment = {
        GIN_MODE                            = "release"
        RETAIL_CATALOG_PERSISTENCE_PROVIDER = "postgres"
        RETAIL_CATALOG_PERSISTENCE_ENDPOINT = "${var.db_host}:5432"
        RETAIL_CATALOG_PERSISTENCE_DB_NAME  = "catalogdb"
        RETAIL_CATALOG_PERSISTENCE_USER     = "retail_user"
      }
      secrets = var.db_password_arn == "" ? {} : { RETAIL_CATALOG_PERSISTENCE_PASSWORD = var.db_password_arn }
    }
    carts = {
      cpu = 256, memory = 512, desired = var.desired_count, public = false
      environment = {
        CART_PERSISTENCE_PROVIDER = "postgres"
        CART_POSTGRES_HOST        = var.db_host
        CART_POSTGRES_PORT        = "5432"
        CART_POSTGRES_DB          = "cartdb"
        CART_POSTGRES_USER        = "retail_user"
        PORT                      = "8080"
      }
      secrets = var.db_password_arn == "" ? {} : { CART_POSTGRES_PASSWORD = var.db_password_arn }
    }
    orders = {
      cpu = 256, memory = 512, desired = var.desired_count, public = false
      environment = {
        GIN_MODE                           = "release"
        RETAIL_ORDERS_PERSISTENCE_ENDPOINT = "${var.db_host}:5432"
        RETAIL_ORDERS_PERSISTENCE_NAME     = "orders"
        RETAIL_ORDERS_PERSISTENCE_USERNAME = "retail_user"
      }
      secrets = var.db_password_arn == "" ? {} : { RETAIL_ORDERS_PERSISTENCE_PASSWORD = var.db_password_arn }
    }
    checkout = {
      cpu = 256, memory = 512, desired = var.desired_count, public = false
      environment = {
        RETAIL_CHECKOUT_PERSISTENCE_PROVIDER  = "redis"
        RETAIL_CHECKOUT_PERSISTENCE_REDIS_URL = "redis://${var.redis_host}:6379"
        RETAIL_CHECKOUT_ENDPOINTS_ORDERS      = "http://orders.${local.ns}:8080"
      }
    }
  }
}

module "ecs" {
  source = "./modules/ecs"

  name_prefix                = local.name_prefix
  environment                = var.environment
  aws_region                 = var.aws_region
  vpc_id                     = module.network.vpc_id
  public_subnet_ids          = module.network.public_subnet_ids
  private_subnet_ids         = module.network.private_subnet_ids
  alb_security_group_id      = module.network.alb_security_group_id
  services_security_group_id = module.network.services_security_group_id
  image_registry             = var.image_registry
  image_tag                  = var.image_tag
  services                   = local.service_definitions
}
