# Ambiente Test. Este archivo se versiona: no contiene secretos (las contraseñas las genera Terraform
# y quedan en Secrets Manager). Estado propio, separado de Dev y Prod:
#   terraform init -reconfigure -backend-config="bucket=<bucket del estado>" -backend-config="key=test/terraform.tfstate"
#   terraform plan -var-file=environments/test.tfvars -var="image_tag=<sha aprobado>"

environment        = "test"
aws_region         = "us-east-1"
vpc_cidr           = "10.20.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

# Lee los repositorios ECR que administra Dev; despliega la misma imagen que pasó por Dev.
manage_shared_resources = false

# AWS Academy (Learner Lab) no permite crear roles IAM: ECS y la Lambda usan LabRole.
# En una cuenta sin esa restricción, null: Terraform crea roles propios con permisos mínimos.
existing_iam_role_name = "LabRole"

# El pipeline lo reemplaza con -var="image_tag=<sha>" puesto después de -var-file.
image_tag     = "dd0abffb390b04109f2a73313c0f666a30dcb357"
desired_count = 1

# Datos: tamaño mínimo, una zona. Test se conserva entre despliegues: deja snapshot al destruirse.
db_instance_class        = "db.t4g.micro"
db_multi_az              = false
db_backup_retention_days = 3
redis_node_type          = "cache.t4g.micro"
redis_transit_encryption = true

db_deletion_protection      = false
db_skip_final_snapshot      = false
secret_recovery_window_days = 7
