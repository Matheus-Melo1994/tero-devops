# Datos del ambiente (issue #34): PostgreSQL en RDS, Redis en ElastiCache y los secretos que usan los servicios.
# Todo queda en subnets privadas y detrás del security group "data": sin ruta ni puerto abierto desde Internet
# (hallazgo del auditor "DB y Redis expuestos").

# ---------- Secretos ----------
# Los valores se generan acá y viven solo en Secrets Manager y en el estado remoto (S3 cifrado);
# nunca en el repositorio ni en los tfvars. Sin caracteres especiales: catalog y orders arman el DSN
# como "clave=valor" sin comillas y un espacio o una comilla lo rompería.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "random_password" "admin" {
  length  = 24
  special = false
}

resource "random_password" "admin_jwt" {
  length  = 64
  special = false
}

locals {
  secret_descriptions = {
    "db-password"      = "Clave de PostgreSQL (usuario ${var.db_username})"
    "admin-password"   = "Clave de ingreso al panel Admin"
    "admin-jwt-secret" = "Clave de firma de los JWT del panel Admin"
  }

  secret_values = {
    "db-password"      = random_password.db.result
    "admin-password"   = random_password.admin.result
    "admin-jwt-secret" = random_password.admin_jwt.result
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secret_descriptions

  name                    = "${var.secrets_prefix}/${each.key}"
  description             = each.value
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each = aws_secretsmanager_secret.this

  secret_id     = each.value.id
  secret_string = local.secret_values[each.key]
}

# ---------- PostgreSQL (RDS) ----------
resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-db"
  description = "Subnets privadas de PostgreSQL (${var.name_prefix})"
  subnet_ids  = var.private_subnet_ids
}

# PostgreSQL 15+ en RDS exige TLS por defecto (rds.force_ssl=1), pero catalog y orders se conectan con
# sslmode=disable y admin usa pg sin ssl. Se desactiva la exigencia para no tocar la app; el tráfico no
# sale de las subnets privadas y el security group solo admite a los servicios. Deuda: habilitar TLS en
# los tres clientes y volver a exigirlo.
resource "aws_db_parameter_group" "this" {
  name        = "${var.name_prefix}-postgres"
  family      = "postgres${split(".", var.db_engine_version)[0]}"
  description = "Parametros de PostgreSQL (${var.name_prefix})"

  parameter {
    name  = "rds.force_ssl"
    value = "0"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier = "${var.name_prefix}-postgres"

  engine                     = "postgres"
  engine_version             = var.db_engine_version
  auto_minor_version_upgrade = true
  instance_class             = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_initial_database
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.data_security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period   = var.db_backup_retention_days
  copy_tags_to_snapshot     = true
  deletion_protection       = var.db_deletion_protection
  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_skip_final_snapshot ? null : "${var.name_prefix}-postgres-final"
}

# ---------- Redis (ElastiCache) ----------
resource "aws_elasticache_subnet_group" "this" {
  name        = "${var.name_prefix}-redis"
  description = "Subnets privadas de Redis (${var.name_prefix})"
  subnet_ids  = var.private_subnet_ids
}

# Un solo nodo: checkout guarda ahí el estado del checkout en curso, que se puede perder sin daño.
# Se usa replication group (y no aws_elasticache_cluster) porque es el recurso que admite cifrado.
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "Redis de checkout (${var.name_prefix})"

  engine               = "redis"
  engine_version       = var.redis_engine_version
  parameter_group_name = "default.redis${split(".", var.redis_engine_version)[0]}"
  node_type            = var.redis_node_type
  num_cache_clusters   = 1
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.data_security_group_id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = var.redis_transit_encryption
  automatic_failover_enabled = false
  snapshot_retention_limit   = 0
  apply_immediately          = true
}
