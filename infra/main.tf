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

# ECR es de la cuenta, no de un ambiente: Dev, Test y Prod despliegan la misma imagen por SHA, sin
# reconstruirla. Los repositorios los crea y administra el estado del ambiente con
# manage_shared_resources = true (Dev); los demás ambientes los leen.
module "ecr" {
  source = "./modules/ecr"
  count  = var.manage_shared_resources ? 1 : 0

  name_prefix = var.project
  services    = var.services
}

# Los repositorios se crearon cuando el módulo no tenía count: se conservan en el estado, sin recrearlos.
moved {
  from = module.ecr
  to   = module.ecr[0]
}

data "aws_ecr_repository" "shared" {
  for_each = var.manage_shared_resources ? toset([]) : toset(var.services)

  name = "${var.project}-${each.key}"
}

# Rol existente para ECS y Lambda cuando la cuenta no permite crear roles (LabRole en AWS Academy).
data "aws_iam_role" "existing" {
  count = var.existing_iam_role_name == null ? 0 : 1

  name = var.existing_iam_role_name
}

locals {
  ecr_repository_urls = var.manage_shared_resources ? module.ecr[0].repository_urls : {
    for k, r in data.aws_ecr_repository.shared : k => r.repository_url
  }

  existing_iam_role_arn = var.existing_iam_role_name == null ? null : data.aws_iam_role.existing[0].arn
}

# PostgreSQL, Redis y los secretos (issue #34). Las contraseñas se generan dentro del módulo.
module "data" {
  source = "./modules/data"

  name_prefix            = local.name_prefix
  secrets_prefix         = "${var.project}/${var.environment}"
  private_subnet_ids     = module.network.private_subnet_ids
  data_security_group_id = module.network.data_security_group_id

  db_instance_class        = var.db_instance_class
  db_multi_az              = var.db_multi_az
  db_backup_retention_days = var.db_backup_retention_days
  db_deletion_protection   = var.db_deletion_protection
  db_skip_final_snapshot   = var.db_skip_final_snapshot

  redis_node_type          = var.redis_node_type
  redis_transit_encryption = var.redis_transit_encryption

  secret_recovery_window_days = var.secret_recovery_window_days
}

locals {
  db_endpoint = "${module.data.db_host}:${module.data.db_port}"

  # Llamadas entre servicios: por el ALB interno, enrutado por path ({internal_url} lo completa el módulo
  # ECS). Cada servicio privado declara las rutas que atiende, que son los prefijos de su API.
  # Las claves coinciden con var.services y con las imágenes que publica el pipeline (tero-<clave>).
  # Las contraseñas no van en environment: entran por secrets desde Secrets Manager, siempre.
  services_config = {
    ui = {
      cpu = 256, memory = 512, desired = var.desired_count, public = true, path = "/"
      environment = {
        RETAIL_UI_ENDPOINTS_CATALOG  = "{internal_url}"
        RETAIL_UI_ENDPOINTS_CARTS    = "{internal_url}"
        RETAIL_UI_ENDPOINTS_CHECKOUT = "{internal_url}"
        RETAIL_UI_ENDPOINTS_ORDERS   = "{internal_url}"
        PORT                         = "8080"
      }
    }
    admin = {
      cpu = 256, memory = 512, desired = var.desired_count, public = true, path = "/admin", db_init = true
      # El frontend de admin llama a /auth/login, /auth/me y /auth/logout: sin esta ruta caerían en ui.
      extra_paths = ["/auth/*"]
      environment = {
        DB_HOST        = module.data.db_host
        DB_PORT        = tostring(module.data.db_port)
        DB_USER        = module.data.db_username
        ADMIN_USERNAME = "admin"
        PORT           = "8080"
      }
      # Los tres son obligatorios: sin ellos admin arranca con las claves por defecto del código.
      secrets = {
        DB_PASSWORD      = module.data.db_password_secret_arn
        ADMIN_PASSWORD   = module.data.admin_password_secret_arn
        ADMIN_JWT_SECRET = module.data.admin_jwt_secret_arn
      }
    }
    catalog = {
      cpu            = 256, memory = 512, desired = var.desired_count, public = false, db_init = true
      internal_paths = ["/catalog", "/catalog/*"]
      environment = {
        GIN_MODE                            = "release"
        RETAIL_CATALOG_PERSISTENCE_PROVIDER = "postgres"
        RETAIL_CATALOG_PERSISTENCE_ENDPOINT = local.db_endpoint
        RETAIL_CATALOG_PERSISTENCE_DB_NAME  = "catalogdb"
        RETAIL_CATALOG_PERSISTENCE_USER     = module.data.db_username
      }
      secrets = { RETAIL_CATALOG_PERSISTENCE_PASSWORD = module.data.db_password_secret_arn }
    }
    # El servicio se llama carts (como en compose y en su ruta /carts), pero su imagen es tero-cart.
    # Espera a db-init: cart no crea cartdb ni su tabla.
    carts = {
      image          = "cart", cpu = 256, memory = 512, desired = var.desired_count, public = false, db_init = true
      internal_paths = ["/carts", "/carts/*"]
      environment = {
        CART_PERSISTENCE_PROVIDER = "postgres"
        CART_POSTGRES_HOST        = module.data.db_host
        CART_POSTGRES_PORT        = tostring(module.data.db_port)
        CART_POSTGRES_DB          = "cartdb"
        CART_POSTGRES_USER        = module.data.db_username
        PORT                      = "8080"
      }
      secrets = { CART_POSTGRES_PASSWORD = module.data.db_password_secret_arn }
    }
    orders = {
      cpu            = 256, memory = 512, desired = var.desired_count, public = false, db_init = true
      internal_paths = ["/orders", "/orders/*"]
      environment = {
        GIN_MODE                           = "release"
        RETAIL_ORDERS_PERSISTENCE_ENDPOINT = local.db_endpoint
        RETAIL_ORDERS_PERSISTENCE_NAME     = module.data.db_initial_database
        RETAIL_ORDERS_PERSISTENCE_USERNAME = module.data.db_username
      }
      secrets = { RETAIL_ORDERS_PERSISTENCE_PASSWORD = module.data.db_password_secret_arn }
    }
    checkout = {
      cpu            = 256, memory = 512, desired = var.desired_count, public = false
      internal_paths = ["/checkout", "/checkout/*"]
      environment = {
        RETAIL_CHECKOUT_PERSISTENCE_PROVIDER  = "redis"
        RETAIL_CHECKOUT_PERSISTENCE_REDIS_URL = module.data.redis_url
        RETAIL_CHECKOUT_ENDPOINTS_ORDERS      = "{internal_url}"
      }
    }
  }

  # Cada servicio usa su repositorio de ECR (tero-<image>, o tero-<servicio> si no declara image);
  # el tag (SHA aprobado por CI) lo agrega el módulo ECS. Un repositorio inexistente falla en el plan.
  service_definitions = {
    for name, cfg in local.services_config : name => merge(cfg, {
      image = local.ecr_repository_urls[try(cfg.image, name)]
    })
  }
}

module "ecs" {
  source = "./modules/ecs"

  name_prefix                    = local.name_prefix
  aws_region                     = var.aws_region
  vpc_id                         = module.network.vpc_id
  public_subnet_ids              = module.network.public_subnet_ids
  private_subnet_ids             = module.network.private_subnet_ids
  alb_security_group_id          = module.network.alb_security_group_id
  internal_alb_security_group_id = module.network.internal_alb_security_group_id
  services_security_group_id     = module.network.services_security_group_id
  image_tag                      = var.image_tag
  services                       = local.service_definitions
  iam_role_arn                   = local.existing_iam_role_arn
  certificate_arn                = var.certificate_arn

  # Crea catalogdb, cartdb y cart_items antes de que arranquen los servicios que usan Postgres.
  db_init = {
    image = var.db_init_image
    sql   = module.data.db_init_sql
    environment = {
      PGHOST            = module.data.db_host
      PGPORT            = tostring(module.data.db_port)
      PGUSER            = module.data.db_username
      PGDATABASE        = module.data.db_initial_database
      PGCONNECT_TIMEOUT = "10"
    }
    secrets = { PGPASSWORD = module.data.db_password_secret_arn }
  }
}

# Dashboard, alarmas y chequeo sintético serverless del ambiente (bloque 8).
module "observability" {
  source = "./modules/observability"

  name_prefix            = local.name_prefix
  environment            = var.environment
  aws_region             = var.aws_region
  alb_url                = "${var.certificate_arn == null ? "http" : "https"}://${module.ecs.alb_dns_name}"
  alb_arn_suffix         = module.ecs.alb_arn_suffix
  target_groups          = module.ecs.target_groups
  cluster_name           = module.ecs.cluster_name
  service_names          = module.ecs.service_names
  log_group_names        = module.ecs.log_group_names
  db_instance_identifier = module.data.db_instance_identifier
  redis_cache_cluster_id = module.data.redis_cache_cluster_id
  iam_role_arn           = local.existing_iam_role_arn
  alarm_email            = var.alarm_email
}
