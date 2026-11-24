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
├── infra/                    infraestructura en Terraform: red, ECR, datos, ECS, observabilidad (ver su README)
├── .github/workflows/
│   ├── ci.yml                pipeline de CI: seguridad, calidad, build, tests, publicación
│   ├── deploy.yml            despliegue continuo Dev → Test → Prod
│   ├── deploy-env.yml        despliegue de un ambiente (lo llama deploy.yml)
│   └── terraform.yml         validación de IaC
├── docs/
│   ├── decisiones.md         decisiones de diseño (ADR)
│   ├── diagramas.md          arquitectura, pipeline y ramas
│   ├── informe-calidad.md    análisis estático (SonarCloud)
│   └── evidencias/           capturas y logs por bloque de la letra
├── .trivyignore.yaml         excepciones revisadas de Trivy (una por CVE, con vencimiento)
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

En AWS estos valores no salen de `.env`: Terraform los genera, los guarda en Secrets Manager y ECS los inyecta en cada tarea (ver [`infra/README.md`](infra/README.md), "Datos y secretos").

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
| Calidad | SonarCloud | Bugs, code smells, duplicación; espera el quality gate "Sonar way" y falla si no aprueba |
| SCA | Trivy fs | Vulnerabilidades en dependencias; bloquea con cualquier CRITICAL/HIGH, tenga o no parche |
| Build | Docker | Las 6 imágenes en paralelo, multi-stage, no-root |
| Escaneo de imagen | Trivy image | Cada imagen antes de publicar; bloquea con cualquier CRITICAL/HIGH |
| Tests | Node test runner | Las 2 pruebas de integración |
| Publicación | GHCR | Solo en push a `main` y si pasaron todos los controles; publica la imagen escaneada, tag por SHA y `latest` |

Orden: secretos → SAST + calidad + SCA → build + escaneo → tests → publicación. Si falla la detección de secretos no corre ningún otro job; SCA además requiere SAST; la publicación solo corre si aprobaron todos los controles.

**Gates de Trivy (bloqueantes desde la issue #59).** Los jobs de SCA y de build usan Trivy v0.76.2 con `severity: CRITICAL,HIGH` e `ignore-unfixed: false`. Cada uno corre dos pasos: un reporte JSON completo (`exit-code: '0'`, solo evidencia) y el gate (`exit-code: '1'`), que corta el job con el código de salida de Trivy. No hay `continue-on-error`. Las únicas excepciones son las de `.trivyignore.yaml`: una por CVE y versión exacta, con justificación y fecha de vencimiento (al vencer, el gate vuelve a bloquear). Los reportes se suben como artifacts aunque el gate falle (`trivy-sca` y `trivy-image-<servicio>`, 30 días).

**Quality gate de SonarCloud (bloqueante).** El job `quality` pasa al scanner `sonar.qualitygate.wait=true` y `sonar.qualitygate.timeout=300`: en lugar de terminar al enviar el análisis, espera el resultado del quality gate y falla si no aprueba. Usa `SonarSource/sonarqube-scan-action@v8`; la versión anterior (`@v5`) ya no tiene soporte y avisa en cada ejecución de una vulnerabilidad conocida.

**Publicación sin reconstruir.** `publish` depende de `gitleaks`, `sast`, `quality`, `sca`, `build` e `integration`: si cualquiera falla, no corre. No vuelve a construir: descarga el `image.tar` que el job de build exportó después de aprobar el gate, comprueba que su ID coincide con el registrado al escanear (`image-id.txt`) y publica esa misma imagen.

`.github/workflows/terraform.yml` corre en PRs que toquen `infra/`: `terraform fmt`, `validate` y `tflint`.

**Verificación de los gates.** Comprobado en local con la misma versión y las mismas opciones de Trivy que usa el pipeline (detalle en `validation.negative_case` del JSON de evidencia):

- Caso aprobado: `trivy fs app/src` y las seis imágenes terminan con código 0.
- Caso negativo: con una dependencia vulnerable agregada solo en una copia temporal (`urllib3==1.26.4` en Cart, 8 HIGH), el gate de SCA y el de la imagen terminan con código 1, y los reportes JSON y de tabla quedan escritos aunque el gate falle. El fixture nunca entró al repositorio.
- El workflow pasa `actionlint` y el ID de una imagen se conserva tras `docker save` / `docker load`.

Primera ejecución en GitHub Actions (PR #62, commit `86576c4`): aprobaron Gitleaks, Semgrep, el SCA, los seis builds con su escaneo de imagen y las pruebas de integración, y se subieron los artifacts `trivy-sca`, `trivy-image-<servicio>` e `image-<servicio>`. El job de SonarCloud esperó el quality gate y falló, porque el gate no aprobó: una vulnerabilidad nueva (`docker:S8544`, dependencias de Python instaladas sin verificar hashes en `app/src/cart/Dockerfile`). Se corrigió fijando los hashes (ver decisiones de Cart más abajo); no se desactivó la regla ni se cambió el gate.

Desde entonces el pipeline completo corre en verde en cada push a `main` (capturas en `docs/evidencias/02-cicd/`).

## Remediación de vulnerabilidades (issue #59)

Escaneos con Trivy 0.76.2, severidades HIGH y CRITICAL, incluyendo las que no tienen parche (`ignore-unfixed: false`). El detalle por hallazgo, los IDs de imagen y las validaciones están en [`docs/evidencias/05-seguridad/remediacion-trivy.json`](docs/evidencias/05-seguridad/remediacion-trivy.json).

| Servicio | Imagen antes (HIGH / CRITICAL) | Imagen después | Qué se hizo |
|---|---|---|---|
| catalog | 51 / 3 | 0 / 0 | Go 1.27.4, `alpine:3.24`, pgx 5.9.0, grpc 1.83.2, otel 1.44.0, `golang.org/x/*` |
| orders | 45 / 2 | 0 / 0 | Go 1.27.4, `alpine:3.24`, pgx 5.9.0, `golang.org/x/*` |
| checkout | 55 / 1 | 0 / 0 | Dependencias actualizadas en `yarn.lock`; solo dependencias de producción en la imagen |
| ui | 10 / 0 | 0 / 0 | `package-lock.json` + `npm ci`; npm y yarn fuera del runtime |
| admin | 10 / 0 | 0 / 0 | `package-lock.json` + `npm ci`; npm y yarn fuera del runtime |
| cart | 52 / 0 | 0 / 0 | Base `python:3.12-alpine`, fastapi 0.163.1 (starlette 1.10.0), dependencias transitivas fijadas con hash |

El SCA (`trivy fs app/src`) pasó de 69 HIGH y 6 CRITICAL a 0. Además ahora cubre los seis servicios: antes UI y Admin no tenían lockfile y Cart solo declaraba sus dependencias directas, así que esa ausencia de hallazgos no era un resultado limpio.

Decisiones:

- **Base de Cart.** `python:3.12-slim` (Debian 13) traía 49 HIGH en paquetes del sistema, 47 de ellos sin parche publicado (util-linux, ncurses, sqlite, systemd, perl). Se reemplazó por `python:3.12-alpine`, manteniendo multi-stage, usuario no-root y las mismas variables. La base alpine publicada tenía 16 HIGH en `krb5-libs` con parche disponible en el repositorio de Alpine; el `apk upgrade` de la etapa final los corrige. Todas las dependencias tienen wheel para musl, por lo que no se compila nada en la imagen.
- **Dependencias de Cart.** starlette 0.38.6 llegaba como transitiva de fastapi 0.115.0. Se subió fastapi a 0.163.1 y prometheus-fastapi-instrumentator a 8.1.0 (la rama compatible con starlette 1.x). `requirements.in` lista las dependencias directas y `requirements.txt` se genera con `pip-compile --generate-hashes`, que fija también las transitivas y el hash de cada paquete; la imagen instala exactamente esa lista (`pip install --require-hashes --no-deps`), que es la que analiza el SCA, y pip rechaza cualquier archivo cuyo hash no coincida.
- **npm fuera del runtime (UI y Admin).** Los 10 HIGH de cada imagen venían de las dependencias del propio npm incluido en `node:22-alpine` (brace-expansion, pacote, sigstore, ip-address, picomatch), no de la aplicación. En ejecución solo se usa `node dist/app.js`, así que la etapa final elimina npm, npx y yarn. La etapa de build los conserva y usa `npm ci` con el lockfile.
- **Admin.** Las pruebas de integración no cubren Admin, por lo que se verificó aparte contra el stack de Compose: acceso sin sesión rechazado (401), login incorrecto (401), login correcto con cookie de sesión, alta de un producto visible desde Catalog, edición, baja y listado de órdenes. 11 comprobaciones aprobadas.

## Infraestructura y despliegue

Toda la infraestructura de AWS está en `infra/` como Terraform, en módulos reutilizables con variables por ambiente (`dev`, `test`, `prod`) y estado remoto en S3:

| Módulo | Qué crea |
|---|---|
| `network` | VPC, subnets públicas y privadas en dos AZ, NAT, security groups |
| `ecr` | Un repositorio por servicio, tags inmutables, escaneo al subir |
| `data` | RDS PostgreSQL, ElastiCache Redis, contraseñas generadas y guardadas en Secrets Manager, inicialización de la base |
| `ecs` | Cluster Fargate, una task definition y un service por microservicio, ALB público (`ui`, `admin`) y ALB interno para las llamadas entre servicios, logs JSON a CloudWatch |
| `observability` | Dashboard, alarmas con aviso por SNS y chequeo sintético serverless (Lambda + EventBridge) |

**Despliegue continuo.** `.github/workflows/deploy.yml` arranca cuando el CI de `main` termina en verde: copia las seis imágenes de GHCR a ECR sin reconstruirlas (mismo digest), despliega **Dev**, luego **Test** y, tras una aprobación manual en el environment `prod` de GitHub, **Prod**. Cada ambiente solo avanza si los servicios quedan estables con la task definition del SHA y el chequeo sintético pasa. Para volver a una versión anterior se ejecuta el mismo workflow a mano con el SHA de un commit de `main` ya aprobado.

El paso a paso para levantar un ambiente desde cero, las particularidades de AWS Academy (LabRole, ALB interno en lugar de Cloud Map, credenciales que vencen), las alarmas con su procedimiento de respuesta y cómo destruir el ambiente están en [`infra/README.md`](infra/README.md).

## Flujo de trabajo

- Rama `main` protegida: todo cambio entra por pull request con al menos una aprobación de otro integrante, conversaciones resueltas y checks en verde.
- Ramas por tema: `feat/`, `fix/`, `ci/`, `docs/`, `test/`.
- Un PR, un tema.

## Documentación

| Documento | Contenido |
|---|---|
| [`docs/decisiones.md`](docs/decisiones.md) | Decisiones de diseño en formato ADR: ramas, ECS vs EKS, registries, credenciales, descubrimiento de servicios, loggers, gates de Sonar y Trivy |
| [`docs/diagramas.md`](docs/diagramas.md) | Arquitectura general, pipeline CI/CD con las etapas de seguridad, estrategia de ramas (fuente editable en draw.io) |
| [`docs/informe-calidad.md`](docs/informe-calidad.md) | Análisis estático: hallazgos de SonarCloud, qué se corrigió, qué se aceptó y recomendaciones |
| [`infra/README.md`](infra/README.md) | Infraestructura, despliegue, alarmas y procedimientos de respuesta, decisiones y limitaciones |
| [`app/tests/integration/README.md`](app/tests/integration/README.md) | Pruebas de integración |
| [`docs/evidencias/`](docs/evidencias/) | Capturas y logs por bloque de la letra (`01-planificacion` … `08-observabilidad`) |

## Lecciones aprendidas

- **Los gates bloqueantes desde el principio ahorran tiempo después.** Semgrep detectó Dockerfiles sin usuario, Trivy obligó a actualizar bases y dependencias, y Sonar frenó un Dockerfile que instalaba paquetes de Python sin verificar hashes. Cada uno se corrigió en el PR donde apareció, no al final.
- **"Sin hallazgos" no siempre es un resultado limpio.** UI y Admin no tenían lockfile y Cart solo declaraba dependencias directas: Trivy no veía nada porque no había nada que escanear. Agregar lockfiles hizo aparecer los hallazgos reales.
- **La imagen que se despliega tiene que ser la que se escaneó.** Publicar desde el `image.tar` del build y copiar a ECR por digest evita que un rebuild silencioso cambie lo que corre en producción.
- **Las restricciones del entorno se documentan, no se esconden.** AWS Academy no permite roles IAM propios, Cloud Map ni OIDC. Cada adaptación quedó parametrizada (una cuenta normal usa roles propios) y registrada como decisión.
- **Un servicio llamado `carts` con una carpeta `cart`** costó un PR: los nombres heredados conviene revisarlos al inicio.
- **Revisar el PR del otro de verdad.** Los comentarios de revisión encontraron el desajuste `carts`/`cart`, un local sin uso y la falta de runbooks antes de que llegaran a `main`.

## Uso de inteligencia artificial

Se usó **Claude (Anthropic)** como asistente durante todo el proyecto, con estos usos:

- Explicación de conceptos y de la letra antes de implementar (multi-stage builds, quality gates, estrategia de despliegue, qué es un runbook).
- Borradores de código de infraestructura (módulo ECS inicial, diagramas en Mermaid/draw.io) y de documentación (ADRs, informe de calidad, este README), siempre revisados, ajustados y validados por el equipo (`terraform validate`, `tflint`, pipeline en verde).
- Revisión de pull requests del compañero: lectura del diff y lista de observaciones, que después se discutieron entre los integrantes.
- Diagnóstico de errores del pipeline (tags de actions, falsos positivos de Sonar, duplicación entre loggers).

Todo el contenido generado fue verificado contra el código, los workflows y la documentación oficial de las herramientas antes de incorporarse. Las decisiones (qué aceptar en Sonar, qué excluir, cómo adaptar a Academy) las tomó el equipo; la IA aportó opciones y argumentos. Ambos integrantes pueden explicar y defender cada parte de lo entregado.
