# Ambiente Dev. Este archivo se versiona: no contiene secretos (las contraseñas las genera Terraform
# y quedan en Secrets Manager). Uso:
#   terraform init -backend-config="key=dev/terraform.tfstate"
#   terraform plan -var-file=environments/dev.tfvars

environment        = "dev"
aws_region         = "us-east-1"
vpc_cidr           = "10.10.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

# El estado de Dev administra los repositorios ECR que comparten los tres ambientes: se aplica primero.
manage_shared_resources = true

# Imágenes: SHA de main cuyo pipeline de CI publicó las seis imágenes (tero-<servicio>:<sha>).
# Antes del primer apply hay que copiarlas a ECR (ver README). El pipeline de deploy lo reemplaza
# con -var="image_tag=<sha>" puesto después de -var-file.
image_tag     = "dd0abffb390b04109f2a73313c0f666a30dcb357"
desired_count = 1

# Datos: lo más chico que ofrece AWS, en una sola zona.
db_instance_class        = "db.t4g.micro"
db_multi_az              = false
db_backup_retention_days = 1
redis_node_type          = "cache.t4g.micro"
redis_transit_encryption = true

# Dev se destruye al terminar cada ventana de trabajo para no pagar NAT, ALB, RDS y Redis por hora:
# sin protección de borrado, sin snapshot final y con los secretos eliminados al instante, así se
# puede volver a crear con los mismos nombres.
db_deletion_protection      = false
db_skip_final_snapshot      = true
secret_recovery_window_days = 0
