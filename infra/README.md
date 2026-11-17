# Infraestructura (Terraform)

Toda la infraestructura de Tero en AWS, salvo el bucket del estado y su tabla de lock, se define acá (bloque 7 de la letra).

## Estructura

```
infra/
├── backend.tf          estado remoto en S3 + lock en DynamoDB (el bucket se pasa en el init)
├── providers.tf        provider AWS con tags por defecto
├── versions.tf         versiones fijadas de Terraform y providers
├── variables.tf        variables raíz
├── main.tf             composición de módulos
├── outputs.tf          outputs con descripción
├── modules/
│   ├── network/        VPC, subnets públicas/privadas, NAT, security groups
│   ├── ecr/            un repositorio por microservicio (compartido por los tres ambientes)
│   ├── data/           RDS PostgreSQL, ElastiCache Redis, secretos e init-db.sql
│   ├── ecs/            cluster Fargate, ALB público, ALB interno, servicios y logs
│   └── observability/  dashboard, alarmas, SNS y chequeo sintético (Lambda)
└── environments/       dev.tfvars, test.tfvars, prod.tfvars (sin secretos; se versionan)
```

## Ambientes

Cada ambiente tiene su VPC y su estado (`<ambiente>/terraform.tfstate` en el mismo bucket), así un `apply`
en uno no puede tocar otro. ECR es de la cuenta: lo administra el estado de Dev (`manage_shared_resources`)
y Test/Prod leen los mismos repositorios, por eso Dev se aplica primero.

| Ambiente | VPC | Tareas por servicio | RDS | Al destruirse |
| --- | --- | --- | --- | --- |
| dev | 10.10.0.0/16 | 1 | una zona, backup 1 día | sin snapshot; se recrea en cada ventana de trabajo |
| test | 10.20.0.0/16 | 1 | una zona, backup 3 días | deja snapshot final |
| prod | 10.30.0.0/16 | 2 | Multi-AZ, backup 7 días, protección de borrado | deja snapshot final |

## Preparar una cuenta (la propia o la de un compañero)

Todos los comandos llevan el perfil de la cuenta; nada lleva el número de cuenta escrito.

1. **Confirmar la cuenta** antes de crear nada:

   ```bash
   export AWS_PROFILE=<perfil> AWS_REGION=us-east-1
   aws sts get-caller-identity --query '[Account,Arn]' --output text
   ```

2. **Backend** (una vez por cuenta). Si `aws s3api head-bucket --bucket <bucket>` responde, ya existe:
   se reutiliza, nunca se crea otro estado vacío. Si no, se crea con los comandos de `backend.tf`. El nombre
   del bucket es único en todo AWS; cada cuenta usa el suyo y se pasa en el init.

   ```bash
   cd infra
   terraform init -reconfigure -backend-config="bucket=<bucket>" -backend-config="key=dev/terraform.tfstate"
   terraform state list
   ```

   Si `state list` muestra recursos, la cuenta ya tiene Dev (o al menos ECR) administrado: seguir en el paso 4.

3. **Repositorios ECR**, solo en una cuenta nueva (es el único uso de `-target`):

   ```bash
   terraform apply -var-file=environments/dev.tfvars -target='module.ecr'
   ```

4. **Imágenes**. El código de Terraform sale de esta rama (o de main con este cambio); las imágenes, de un
   commit de main cuyo CI terminó bien y publicó las seis en GHCR. Ese SHA es `image_tag`; no tienen por qué
   ser el mismo commit. Se copian sin reconstruir y se comprueba que el digest en ECR sea el de GHCR
   (los tags de ECR son inmutables). El pipeline de deploy hace lo mismo con `skopeo copy --preserve-digests`.

   ```bash
   SHA=<image_tag>
   ECR=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com
   aws ecr get-login-password | docker login --username AWS --password-stdin "$ECR"
   for s in admin cart catalog checkout orders ui; do
     src="ghcr.io/matheus-melo1994/tero-$s:$SHA"
     docker pull "$src" && docker tag "$src" "$ECR/tero-$s:$SHA" && docker push "$ECR/tero-$s:$SHA"
     echo "$s ghcr=$(docker buildx imagetools inspect "$src" --format '{{json .Manifest}}' | jq -r .digest)" \
          "ecr=$(aws ecr describe-images --repository-name "tero-$s" --image-ids imageTag=$SHA --query 'imageDetails[0].imageDigest' --output text)"
   done
   ```

5. **Plan completo y apply** de Dev, revisando el plan antes de aplicarlo:

   ```bash
   terraform plan -var-file=environments/dev.tfvars -var="image_tag=$SHA" -out=dev.tfplan
   terraform apply dev.tfplan
   terraform output alb_url
   ```

   Para Test o Prod: `-reconfigure` con `key=test/terraform.tfstate` (o `prod/`) y su tfvars.

6. **Destruir Dev** al terminar: NAT, los dos ALB, RDS, Redis y las tareas se cobran por hora. Los
   repositorios ECR (y sus imágenes) se conservan:

   ```bash
   terraform destroy -var-file=environments/dev.tfvars -target=module.observability -target=module.ecs -target=module.data -target=module.network
   ```

## AWS Academy (Learner Lab)

Comprobado en la cuenta del lab (con la API y `aws iam simulate-principal-policy`): niega
`servicediscovery:*`, `iam:CreateRole` e `iam:CreateOpenIDConnectProvider`. Por eso:

- **Descubrimiento**: los servicios se llaman por un **ALB interno** en las subnets privadas, enrutado por
  path (`/catalog`, `/carts`, `/checkout`, `/orders`), en lugar de Cloud Map. El ALB además reparte carga y
  saca de rotación las tareas que no pasan `/health`.
- **Roles**: ECS y la Lambda usan `LabRole` (`existing_iam_role_name` en los tfvars). En una cuenta sin esa
  restricción se deja en `null` y Terraform crea roles propios con permisos mínimos.
- **Pipeline**: el lab tampoco permite OIDC; el pipeline usa las credenciales temporales del lab como
  secretos del environment, que vencen al cerrar la sesión y hay que renovar antes de cada despliegue.

## Despliegue continuo

`.github/workflows/deploy.yml` arranca cuando el workflow CI termina bien en un push a main (o a mano con
un SHA de main ya aprobado, para re-desplegar o volver atrás). Ese CI ya pasó secretos, SAST, SonarCloud,
Trivy, escaneo de imagen, pruebas de integración y publicó las imágenes. El deploy no construye nada:

1. Comprueba que el CI de ese SHA haya terminado bien y lee el digest de las seis imágenes en GHCR.
2. Copia cada manifiesto a ECR con el mismo digest (ECR es compartido: una sola vez).
3. Despliega **Dev → Test → Prod** con `deploy-env.yml`: verifica los digests en ECR, `terraform plan`
   y `apply` con `image_tag=<sha>`, espera los servicios estables con la task definition de ese SHA
   (si el circuit breaker de ECS hizo rollback, el job falla) y corre el chequeo sintético.
   Cada ambiente solo arranca si el anterior pasó.

Configuración manual en GitHub (Settings → Environments), por única vez:

| Environment | Variables | Secretos | Protección |
| --- | --- | --- | --- |
| dev, test, prod | `TF_STATE_BUCKET` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | prod: revisores requeridos |

## Observabilidad

Por ambiente: dashboard `tero-<ambiente>-operacion` en CloudWatch y alarmas que avisan al tópico SNS
`tero-<ambiente>-alarms` (con `alarm_email` se suscribe un correo, que hay que confirmar).

El **chequeo sintético** es una Lambda (Python 3.12, sin VPC) que EventBridge ejecuta cada 5 minutos: pide
`/health`, `/api/catalog/products` (ui → ALB interno → catalog → RDS) y `/admin/` por el ALB público, y
publica `Success`, `LatencyMs` y `AllChecksPassed` en `Tero/Synthetics`. Prueba manual:
`aws lambda invoke --function-name tero-dev-synthetic out.json && cat out.json`.

| Alarma | Se dispara cuando | Primera respuesta |
| --- | --- | --- |
| `<amb>-synthetic-failing` | un chequeo sintético falla dos veces seguidas (10 min) o deja de correr | En el log de la Lambda, ver qué chequeo y con qué `error_type`/`status`. Seguir con la alarma de destinos sanos del servicio involucrado. |
| `<amb>-<servicio>-no-healthy-targets` | el ALB no tiene ninguna tarea sana del servicio por 3 minutos | `aws ecs describe-services` (eventos y `stoppedReason` de las tareas); logs del servicio y de `db-init`. Si fue un despliegue, el circuit breaker vuelve a la revisión anterior; si no, redesplegar el último SHA estable. |
| `<amb>-alb-target-5xx` | los servicios devuelven más de 5 respuestas 5xx en 5 minutos | Widget "Últimos errores" del dashboard: `service`, `route` y `error_type`. Revisar RDS/Redis (conexiones, CPU) y el último despliegue. |
| `<amb>-application-errors` | más de 10 logs con `level=error` en 5 minutos (los seis servicios) | Mismo widget; el gráfico "Logs con level=error por servicio" muestra cuál. |

## Datos y secretos

- **PostgreSQL** (RDS, subnets privadas): una instancia con las tres bases de Tero. RDS crea `orders`;
  `catalogdb`, `cartdb` y la tabla `cart_items` las crea `modules/data/init-db.sql`.
- **Inicialización**: los servicios que usan Postgres (admin, carts, catalog y orders) llevan un contenedor
  previo `db-init` que ejecuta ese script con `psql` y termina; el servicio arranca solo si salió bien.
  El script es idempotente, así que corre en cada arranque sin efecto una vez creadas las bases.
- **Redis** (ElastiCache, subnets privadas): un nodo, cifrado en reposo y TLS en tránsito (`rediss://`).
- **Secretos**: Terraform genera la contraseña de Postgres, `ADMIN_PASSWORD` y `ADMIN_JWT_SECRET` y los guarda
  en Secrets Manager (`tero/<ambiente>/...`). ECS los inyecta al arrancar cada tarea; no están en el
  repositorio ni en los tfvars. Los valores sí quedan en el estado de Terraform: por eso el bucket del
  estado va cifrado, versionado y con el acceso público bloqueado.

## Validación sin credenciales

```bash
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
```

Corren en `.github/workflows/terraform.yml` junto con tflint.

## Decisiones y limitaciones

- Un NAT Gateway por ambiente (no uno por AZ): contiene costo; si cae esa zona, las tareas pierden salida a Internet.
- Se despliega siempre por SHA de commit (`image_tag` rechaza `latest`) y los tags de ECR son inmutables.
- **HTTP en el ALB público**: sin dominio ni certificado en el lab, la tienda se sirve por HTTP. Con
  `certificate_arn` (ACM) el ALB sirve HTTPS con TLS 1.2+ y redirige 80 → 443. Test y Prod no deberían
  exponerse sin certificado.
- **Sin TLS hacia RDS** (`rds.force_ssl=0`): catalog, orders y admin se conectan sin TLS. El tráfico no sale
  de las subnets privadas y el security group solo admite a los servicios. Pendiente: TLS en esos clientes.
- **Usuario maestro de RDS**: los servicios usan el usuario maestro (`retail_user`), igual que en
  docker-compose. Pendiente: un usuario por servicio con permisos solo sobre su base.
- **Permisos de LabRole**: en AWS Academy las tareas y la Lambda corren con un rol amplio que no se puede
  acotar. En una cuenta propia, los roles que crea Terraform solo leen los tres secretos del ambiente.
