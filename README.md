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
| Desarrollar un servicio | Go 1.27 (catalog, orders) · Node 22 (ui, admin, checkout) · Python 3.12 (carts) |

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

## Remediación de vulnerabilidades (issue #59)

Escaneos con Trivy 0.76.2, severidades HIGH y CRITICAL, incluyendo las que no tienen parche (`ignore-unfixed: false`). El detalle por hallazgo, los IDs de imagen y las validaciones están en [`docs/evidencias/05-seguridad/remediacion-trivy.json`](docs/evidencias/05-seguridad/remediacion-trivy.json).

| Servicio | Imagen antes (HIGH / CRITICAL) | Imagen después | Qué se hizo |
|---|---|---|---|
| catalog | 51 / 3 | 0 / 0 | Go 1.27.4, `alpine:3.24`, pgx 5.9.0, grpc 1.83.2, otel 1.44.0, `golang.org/x/*` |
| orders | 45 / 2 | 0 / 0 | Go 1.27.4, `alpine:3.24`, pgx 5.9.0, `golang.org/x/*` |
| checkout | 55 / 1 | 0 / 0 | Dependencias actualizadas en `yarn.lock`; solo dependencias de producción en la imagen |
| ui | 10 / 0 | 0 / 0 | `package-lock.json` + `npm ci`; npm y yarn fuera del runtime |
| admin | 10 / 0 | 0 / 0 | `package-lock.json` + `npm ci`; npm y yarn fuera del runtime |
| cart | 52 / 0 | 0 / 0 | Base `python:3.12-alpine`, fastapi 0.163.1 (starlette 1.10.0), dependencias transitivas fijadas |

El SCA (`trivy fs app/src`) pasó de 69 HIGH y 6 CRITICAL a 0. Además ahora cubre los seis servicios: antes UI y Admin no tenían lockfile y Cart solo declaraba sus dependencias directas, así que esa ausencia de hallazgos no era un resultado limpio.

Decisiones:

- **Base de Cart.** `python:3.12-slim` (Debian 13) traía 49 HIGH en paquetes del sistema, 47 de ellos sin parche publicado (util-linux, ncurses, sqlite, systemd, perl). Se reemplazó por `python:3.12-alpine`, manteniendo multi-stage, usuario no-root y las mismas variables. La base alpine publicada tenía 16 HIGH en `krb5-libs` con parche disponible en el repositorio de Alpine; el `apk upgrade` de la etapa final los corrige. Todas las dependencias tienen wheel para musl, por lo que no se compila nada en la imagen.
- **Dependencias de Cart.** starlette 0.38.6 llegaba como transitiva de fastapi 0.115.0. Se subió fastapi a 0.163.1 y prometheus-fastapi-instrumentator a 8.1.0 (la rama compatible con starlette 1.x). `requirements.in` lista las dependencias directas y `requirements.txt` se genera con `pip-compile` fijando también las transitivas; la imagen instala exactamente esa lista (`pip install --no-deps`), que es la que analiza el SCA.
- **npm fuera del runtime (UI y Admin).** Los 10 HIGH de cada imagen venían de las dependencias del propio npm incluido en `node:22-alpine` (brace-expansion, pacote, sigstore, ip-address, picomatch), no de la aplicación. En ejecución solo se usa `node dist/app.js`, así que la etapa final elimina npm, npx y yarn. La etapa de build los conserva y usa `npm ci` con el lockfile.
- **Admin.** Las pruebas de integración no cubren Admin, por lo que se verificó aparte contra el stack de Compose: acceso sin sesión rechazado (401), login incorrecto (401), login correcto con cookie de sesión, alta de un producto visible desde Catalog, edición, baja y listado de órdenes. 11 comprobaciones aprobadas.

## Infraestructura

Toda la infraestructura de AWS está en `infra/` como Terraform: VPC con subnets públicas y privadas, security groups, repositorios ECR, estado remoto en S3 y variables por ambiente (`dev`, `test`, `prod`). Detalle en [`infra/README.md`](infra/README.md).

Pendiente (requiere cuenta de AWS): ECS, RDS, ElastiCache, Lambda, y el despliegue automatizado desde el pipeline.

## Flujo de trabajo

- Rama `main` protegida: todo cambio entra por pull request con al menos una aprobación de otro integrante, conversaciones resueltas y checks en verde.
- Ramas por tema: `feat/`, `fix/`, `ci/`, `docs/`, `test/`.
- Un PR, un tema.

## Evidencias

`docs/evidencias/` contiene capturas y logs organizados por bloque de la letra (`01-planificacion` … `09-documentacion`).
