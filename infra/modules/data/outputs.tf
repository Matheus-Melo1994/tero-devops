output "db_instance_identifier" {
  description = "Identificador de la instancia RDS (dimensión DBInstanceIdentifier de sus métricas)."
  value       = aws_db_instance.this.identifier
}

output "redis_cache_cluster_id" {
  description = "Nodo de ElastiCache (dimensión CacheClusterId de sus métricas)."
  value       = sort(aws_elasticache_replication_group.this.member_clusters)[0]
}

output "db_host" {
  description = "Host de PostgreSQL (endpoint de RDS, sin puerto)."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "Puerto de PostgreSQL."
  value       = aws_db_instance.this.port
}

output "db_username" {
  description = "Usuario de PostgreSQL que usan los servicios."
  value       = aws_db_instance.this.username
}

output "db_initial_database" {
  description = "Base creada por RDS; a ella se conecta db-init para crear las otras dos."
  value       = aws_db_instance.this.db_name
}

output "db_init_sql" {
  description = "Script idempotente que crea catalogdb, cartdb y la tabla cart_items."
  value       = file("${path.module}/init-db.sql")
}

output "redis_url" {
  description = "URL de Redis para checkout (rediss:// si hay TLS en tránsito)."
  value       = "${var.redis_transit_encryption ? "rediss" : "redis"}://${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
}

# Los ARN salen de la versión (no del secreto) para que quien los use espere a que el valor exista.
output "db_password_secret_arn" {
  description = "ARN del secreto con la contraseña de PostgreSQL."
  value       = aws_secretsmanager_secret_version.this["db-password"].arn
}

output "admin_password_secret_arn" {
  description = "ARN del secreto ADMIN_PASSWORD."
  value       = aws_secretsmanager_secret_version.this["admin-password"].arn
}

output "admin_jwt_secret_arn" {
  description = "ARN del secreto ADMIN_JWT_SECRET."
  value       = aws_secretsmanager_secret_version.this["admin-jwt-secret"].arn
}
