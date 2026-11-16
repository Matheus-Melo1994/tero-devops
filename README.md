# Tero DevOps

Tero es un marketplace compuesto por 6 microservicios (UI, Admin, Catalog, Carts, Checkout, Orders) con PostgreSQL y Redis. Este repositorio contiene la aplicación, su infraestructura como código, los pipelines de CI/CD y la documentación del obligatorio de DevOps (ORT, 2026).

Equipo: Matheus Melo, Gastón Da Rosa.

## Estructura del repositorio

```
tero-devops/
├── app/                      aplicación
│   ├── src/<servicio>/       código y Dockerfile de cada microservicio
│   ├── tests/integration/    pruebas de integración (ver su README)
│   ├── docker-compose.yml    entorno local completo
│   └── .env.example          plantilla de variables de entorno
├── infra/                    infraestructura en Terraform (ver su README)
├── .github/workflows/
│   ├── ci.yml                pipeline de CI: seguridad, calidad, build, tests, publicación
│   └── terraform.yml         validación de IaC
├── docs/evidencias/          capturas y logs por bloque de la letra
└── sonar-project.properties  configuración de SonarCloud
```

## Prerequisitos

| Para | Herramienta |
|---|---|
| Levantar la app local | Docker Desktop (Compose v2.24+) |
| Trabajar en la infraestructura | Terraform >= 1.6, AWS CLI |
| Desarrollar un servicio | Go 1.24 (catalog, orders) · Node 22 (ui, admin, checkout) · Python 3.12 (carts) |

No hace falta instalar Go, Node ni Python para levantar la app: todo corre en contenedores.

## Variables de entorno

Se definen en `app/.env`, que **no se versiona** (está en `.gitignore`). Copiar la plantilla y completar:

```bash
cp app/.env.example app/.env
```

| Variable | Uso | Nota |
|---|---|---|
| `POSTGRES_USER` | Usuario de PostgreSQL para todos los servicios | Mantener `retail_user`: lo usa `app/init-db.sql` |
| `POSTGRES_PASSWORD` | Contraseña de PostgreSQL | Elegir una propia |
| `ADMIN_USERNAME` | Usuario del panel Admin | |
| `ADMIN_PASSWORD` | Contraseña del panel Admin | Elegir una propia |
| `ADMIN_JWT_SECRET` | Secreto para firmar sesiones de Admin | Cadena aleatoria larga |

Cambiar la contraseña en `.env` no modifica una base ya inicializada: hay que borrar el volumen (`docker compose down -v`).

En AWS estos valores no salen de `.env`: se guardan en Secrets Manager y se inyectan en las tareas de ECS (pendiente, bloque 7).

## Ejecución local

Desde la raíz del repositorio, con `app/.env` completo:

```bash
docker compose --env-file app/.env -f app/docker-compose.yml up -d --build
```

| Servicio | URL |
|---|---|
| Tienda (UI) | http://localhost:8080 |
| Panel Admin | http://localhost:8081 |

PostgreSQL y Redis no publican puertos en el host: solo son accesibles desde la red de Compose.

Para detener conservando datos: `docker compose --env-file app/.env -f app/docker-compose.yml down`. Para detener y borrar la base: agregar `-v`.

## Pruebas de integración

Dos casos (catálogo/carrito y compra/orden) que corren contra el stack completo por HTTP, sin instalar nada en el host:

```bash
docker compose --env-file app/.env -p tero-integration \
  -f app/docker-compose.yml -f app/tests/integration/compose.yml \
  up --build --abort-on-container-exit --exit-code-from integration-tests \
  --attach integration-tests integration-tests
```

Resultado esperado: **2 aprobadas, 0 fallidas, código de salida 0**. Detalle de los casos, limitaciones y resultados en [`app/tests/integration/README.md`](app/tests/integration/README.md).

## Pipeline de CI

`.github/workflows/ci.yml` corre en cada pull request y en cada push a `main`:

| Etapa | Herramienta | Qué hace |
|---|---|---|
| Secretos | Gitleaks | Escanea todo el historial; falla si encuentra credenciales |
| SAST | Semgrep | Análisis estático de seguridad (reglas default + OWASP Top 10) |
| Calidad | SonarCloud | Bugs, code smells, duplicación; quality gate "Sonar way" |
| SCA | Trivy fs | Vulnerabilidades en dependencias (CRITICAL/HIGH con parche) |
| Build | Docker | Las 6 imágenes en paralelo, multi-stage, no-root |
| Escaneo de imagen | Trivy image | Cada imagen antes de publicar |
| Tests | Node test runner | Las 2 pruebas de integración |
| Publicación | GHCR | Solo en push a `main`, tag por SHA y `latest` |

Orden: secretos → SAST + calidad + SCA → build + escaneo → tests → publicación. Si una etapa falla, las siguientes no corren.

**Estado de los gates de Trivy:** configurados como informativos (`exit-code: 0`) hasta remediar los hallazgos del primer escaneo (133 vulnerabilidades con parche en catalog, orders y checkout). Se vuelven bloqueantes en el PR de remediación.

`.github/workflows/terraform.yml` corre en PRs que toquen `infra/`: `terraform fmt`, `validate` y `tflint`.

## Infraestructura

Toda la infraestructura de AWS está en `infra/` como Terraform: VPC con subnets públicas y privadas, security groups, repositorios ECR, estado remoto en S3 y variables por ambiente (`dev`, `test`, `prod`). Detalle en [`infra/README.md`](infra/README.md).

Pendiente (requiere cuenta de AWS): ECS, RDS, ElastiCache, Lambda, y el despliegue automatizado desde el pipeline.

## Flujo de trabajo

- Rama `main` protegida: todo cambio entra por pull request con al menos una aprobación de otro integrante, conversaciones resueltas y checks en verde.
- Ramas por tema: `feat/`, `fix/`, `ci/`, `docs/`, `test/`.
- Un PR, un tema.

## Evidencias

`docs/evidencias/` contiene capturas y logs organizados por bloque de la letra (`01-planificacion` … `09-documentacion`).
