# Infraestructura (Terraform)

Toda la infraestructura de Tero en AWS, salvo el bucket del estado, se define acá (bloque 7 de la letra).

## Estructura

```
infra/
├── backend.tf          estado remoto en S3 + lock en DynamoDB
├── providers.tf        provider AWS con tags por defecto
├── versions.tf         versiones fijadas de Terraform y providers
├── variables.tf        variables raíz
├── main.tf             composición de módulos
├── outputs.tf          outputs con descripción
├── modules/
│   ├── network/        VPC, subnets públicas/privadas, NAT, security groups
│   ├── ecr/            un repositorio por microservicio
│   ├── data/           RDS PostgreSQL, ElastiCache Redis, secretos e init-db.sql
│   └── ecs/            cluster Fargate, ALB, servicios, Cloud Map, logs
└── environments/
    └── dev.tfvars      valores de Dev (sin secretos; se versiona)
```

## Prerequisitos

- Terraform >= 1.6
- AWS CLI con credenciales configuradas (`aws configure`)
- Bucket S3 y tabla DynamoDB para el estado (ver `backend.tf`, se crean una sola vez a mano)

## Uso

```bash
cd infra
terraform init -backend-config="key=dev/terraform.tfstate"
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

### Primer despliegue de un ambiente

Los servicios de ECS bajan `tero-<servicio>:<image_tag>` desde ECR, así que las imágenes tienen que estar
ahí antes de crear los servicios. El pipeline de CI las publica en GHCR; hasta que exista el workflow de
deploy se copian a mano:

```bash
# 1. Solo los repositorios (no tienen costo por hora)
terraform apply -var-file=environments/dev.tfvars -target=module.ecr

# 2. Copiar las seis imágenes del SHA que figura en image_tag
SHA=<image_tag de environments/dev.tfvars>
ECR=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$ECR"
for s in catalog orders ui admin checkout cart; do
  docker pull "ghcr.io/matheus-melo1994/tero-$s:$SHA"
  docker tag  "ghcr.io/matheus-melo1994/tero-$s:$SHA" "$ECR/tero-$s:$SHA"
  docker push "$ECR/tero-$s:$SHA"
done

# 3. El resto: red, NAT, datos, ALB y servicios
terraform apply -var-file=environments/dev.tfvars
```

El paso 3 crea recursos que se cobran por hora aunque la aplicación no reciba tráfico (NAT Gateway, ALB,
RDS, ElastiCache y las tareas Fargate). Dev se levanta para trabajar y se destruye al terminar. Los
repositorios de ECR se dejan (tienen las imágenes y no se cobran por hora), por eso el destroy va por módulo:

```bash
terraform destroy -var-file=environments/dev.tfvars -target=module.ecs -target=module.data -target=module.network
```

## Datos y secretos

- **PostgreSQL** (RDS, subnets privadas): una instancia con las tres bases de Tero. RDS crea `orders`;
  `catalogdb`, `cartdb` y la tabla `cart_items` las crea `modules/data/init-db.sql`.
- **Inicialización**: los servicios que usan Postgres (catalog, cart, orders, admin) llevan un contenedor
  previo `db-init` que ejecuta ese script con `psql` y termina; el servicio arranca solo si salió bien.
  El script es idempotente, así que corre en cada arranque sin efecto una vez creadas las bases.
- **Redis** (ElastiCache, subnets privadas): un nodo, cifrado en reposo y TLS en tránsito (`rediss://`).
- **Secretos**: Terraform genera la contraseña de Postgres, `ADMIN_PASSWORD` y `ADMIN_JWT_SECRET` y los guarda
  en Secrets Manager (`tero/<ambiente>/...`). ECS los inyecta al arrancar cada tarea; no están en el
  repositorio ni en los tfvars. Los valores sí quedan en el estado de Terraform: por eso el bucket del
  estado va cifrado y con acceso restringido. Para leer uno:

  ```bash
  aws secretsmanager get-secret-value --secret-id tero/dev/admin-password --query SecretString --output text
  ```

## Validación sin credenciales

```bash
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
```

## Decisiones

- Un NAT Gateway por ambiente (no uno por AZ): contiene costo; aceptable para este alcance.
- ECR compartido entre ambientes: la misma imagen por SHA se promueve de Dev a Prod sin reconstruir.
- Estado por ambiente en keys separadas del mismo bucket: un `apply` en Dev no puede afectar Prod.
- Se despliega siempre por SHA de commit (`image_tag` rechaza `latest`): se sabe qué código corre en cada ambiente.
- `rds.force_ssl=0`: catalog, orders y admin se conectan a Postgres sin TLS. El tráfico no sale de las subnets
  privadas y el security group solo admite a los servicios. Deuda: habilitar TLS en esos clientes.
- Los servicios usan el usuario maestro de RDS (`retail_user`), igual que en docker-compose. Deuda: un
  usuario por servicio con permisos solo sobre su base.
