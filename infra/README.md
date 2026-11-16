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
│   └── ecr/            un repositorio por microservicio
└── environments/
    ├── dev.tfvars
    ├── test.tfvars
    └── prod.tfvars
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

Para Test o Prod, cambiar `dev` por `test` o `prod` en ambos lugares.

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
