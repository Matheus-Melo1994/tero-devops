# Decisiones de diseño (ADR)

Registro corto de las decisiones más relevantes del proyecto y por qué se tomaron. Cada una sigue el mismo
formato: contexto, decisión, alternativas consideradas y consecuencias. Las decisiones y limitaciones
propias de la infraestructura (NAT único, HTTP sin certificado, TLS a RDS, usuario maestro, LabRole)
están en [`infra/README.md`, sección "Decisiones y limitaciones"](../infra/README.md#decisiones-y-limitaciones).

## ADR-01 — Estrategia de ramas: GitHub Flow con `main` protegida

**Contexto.** Equipo de dos personas, entregas chicas y frecuentes, un solo producto desplegable.

**Decisión.** Una rama `main` siempre desplegable y ramas cortas `feat/…`, `fix/…`, `docs/…` que entran
por Pull Request con al menos una aprobación del otro integrante, conversaciones resueltas y sin bypass.
No hay ramas `develop` ni `release`.

**Alternativas.** Git Flow (develop + release + hotfix): más ceremonia de la que necesita un equipo de dos
con despliegue continuo.

**Consecuencias.** Cada cambio pasa por revisión cruzada y por el pipeline completo antes de llegar a
`main`; el deploy arranca solo desde `main`. El costo es que una rama larga se desactualiza rápido y hay
que traer `main` seguido.

## ADR-02 — Orquestación: ECS Fargate en lugar de EKS

**Contexto.** Tero son 6 microservicios chicos, sin necesidad de operadores, CRDs ni autoscaling complejo.

**Decisión.** ECS con Fargate: un cluster por ambiente, una task definition y un service por
microservicio, sin administrar nodos.

**Alternativas.** EKS: más flexible, pero obliga a administrar el plano de nodos, add-ons y manifiestos, y
el control plane tiene costo fijo por hora. Docker en una EC2: no cumple el requisito de orquestación en la
nube.

**Consecuencias.** Menos superficie para operar y aprender, rollback automático con circuit breaker,
integración directa con ALB, CloudWatch y Secrets Manager. Se pierde portabilidad: los manifiestos son de
ECS, no de Kubernetes.

## ADR-03 — Dos registries: GHCR en CI y ECR para el despliegue

**Contexto.** El pipeline corre en GitHub Actions y publica imágenes con `GITHUB_TOKEN` sin configurar
credenciales de AWS. Fargate lee más rápido y sin credenciales externas desde ECR de la misma cuenta.

**Decisión.** CI publica `ghcr.io/…/tero-<servicio>:<sha>` después de pasar todos los gates. El workflow
de deploy copia ese manifiesto a ECR sin reconstruirlo y verifica que el digest sea el mismo. Los tags de
ECR son inmutables.

**Alternativas.** Publicar directo en ECR desde CI (requiere credenciales de AWS en el job de build, que
hoy vencen por sesión). Construir de nuevo en el deploy (la imagen desplegada ya no sería la escaneada).

**Consecuencias.** La imagen que corre en AWS es exactamente la que pasó Trivy y las pruebas de
integración. Un paso más en el deploy (la copia) y dos lugares donde viven las imágenes.

## ADR-04 — Credenciales de AWS en GitHub como secrets, no OIDC

**Contexto.** La cuenta es un Learner Lab de AWS Academy: no permite crear roles IAM ni proveedores de
identidad, y sus credenciales vencen al cerrar la sesión.

**Decisión.** Cada environment de GitHub (`dev`, `test`, `prod`) guarda `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY` y `AWS_SESSION_TOKEN` del lab, que se renuevan a mano antes de desplegar.

**Alternativas.** OIDC entre GitHub Actions y AWS con un rol por ambiente: es la práctica recomendada y lo
que se usaría en una cuenta propia, pero no se puede crear en Academy.

**Consecuencias.** No hay credenciales de larga duración en el repo ni en el pipeline, pero el deploy
depende de una renovación manual. El módulo de Terraform acepta `existing_iam_role_name = null` para crear
roles propios en una cuenta sin esa restricción.

## ADR-05 — Descubrimiento de servicios con ALB interno en lugar de Cloud Map

**Contexto.** Los servicios se llaman entre sí por nombre (por ejemplo `ui → catalog`). Cloud Map
(service discovery de ECS) es la opción natural, pero AWS Academy no permite crearlo.

**Decisión.** Un ALB interno por ambiente, con una regla por servicio según el path; las URLs internas se
inyectan como variables de entorno al crear el ambiente.

**Alternativas.** Cloud Map (DNS privado `<servicio>.<amb>.tero.local`): más simple y sin costo por hora,
descartado por la restricción del lab. IPs fijas: inviable con tareas que se reemplazan.

**Consecuencias.** Un ALB más por ambiente (costo por hora) y un salto extra en cada llamada interna, a
cambio de health checks y balanceo también entre servicios.

## ADR-06 — Un logger propio por servicio en lugar de una librería compartida

**Contexto.** Tero es políglota (TypeScript, Go y Python) y el bloque de observabilidad pide logs JSON con
un contrato común (`timestamp`, `service`, `level`, `message`, `request_id`…).

**Decisión.** Cada servicio tiene su logger mínimo en su propio lenguaje, siguiendo el mismo contrato de
campos. SonarCloud excluye esos archivos del cálculo de duplicación.

**Alternativas.** Un paquete compartido por lenguaje: tres paquetes, tres pipelines de publicación y un
acoplamiento que no se justifica para unas 30 líneas por servicio.

**Consecuencias.** Algo de código parecido en 6 lugares, a cambio de servicios independientes y
desplegables por separado. El contrato de campos queda documentado en
`docs/evidencias/08-observabilidad/logs-json.md`.

## ADR-07 — Quality gate de SonarCloud: "Sonar way" sin cobertura

**Contexto.** Tero no trae tests unitarios y agregarlos a 6 servicios quedaba fuera del alcance. El plan
gratuito de SonarCloud no permite editar el quality gate.

**Decisión.** Se usa el gate por defecto "Sonar way" (bugs, vulnerabilidades, hotspots, smells y
duplicación en código nuevo) y se excluye la cobertura con `sonar.coverage.exclusions`. La calidad
funcional se cubre con las pruebas de integración del pipeline.

**Alternativas.** Escribir tests unitarios mínimos solo para subir el porcentaje: maquillaje, no calidad.
Desactivar el gate: perderíamos el bloqueo por bugs y vulnerabilidades.

**Consecuencias.** El gate sigue bloqueando lo que importa (seguridad y mantenibilidad) y el informe de
calidad deja registrado que la cobertura no se mide y por qué.

## ADR-08 — Gates de Trivy bloqueantes con excepciones acotadas y con vencimiento

**Contexto.** Trivy escanea dependencias e imágenes en CRITICAL/HIGH con `ignore-unfixed: false`. Hay CVEs
sin parche en ninguna versión que bloquearían el pipeline indefinidamente.

**Decisión.** El gate bloquea siempre; una excepción solo entra en `.trivyignore.yaml` si se limita a un
CVE y a una versión exacta, explica por qué no aplica al código de Tero y tiene fecha de vencimiento. Al
vencer, el gate vuelve a bloquear y la excepción se revisa.

**Alternativas.** `ignore-unfixed: true` (ignora todo lo que no tiene parche, sin revisarlo). Bajar la
severidad a CRITICAL solo.

**Consecuencias.** Pipeline estricto por defecto con una válvula de escape auditable. Hoy hay una
excepción (CVE-2026-112366 en `picomatch`, código no alcanzable desde `ui`), registrada en
`docs/evidencias/05-seguridad`.
