# tero-devops

Tero es una tienda compuesta por UI, Admin, Catalog, Carts, Checkout y Orders, con PostgreSQL y Redis. El código y Docker Compose están en `app/`.

## Ejecución local

Requisitos: Docker con motor Linux y Docker Compose 2.24.4 o superior. Desde la raíz del repositorio:

```powershell
Copy-Item app/.env.example app/.env
```

Completar `app/.env` antes del primer arranque. Conservar `POSTGRES_USER=retail_user`, utilizado por `app/init-db.sql`. Definir contraseñas propias para `POSTGRES_PASSWORD` y `ADMIN_PASSWORD`, el usuario `ADMIN_USERNAME` y un secreto aleatorio largo para `ADMIN_JWT_SECRET`. El archivo real está excluido de Git. No sobrescribir un `.env` existente; cambiar la contraseña en ese archivo no modifica una base ya inicializada.

```powershell
docker compose --env-file app/.env -p tero-manual -f app/docker-compose.yml up -d --build
```

La tienda queda en <http://localhost:8080> y Admin en <http://localhost:8081>; ambos puertos deben estar libres. PostgreSQL y Redis solo son accesibles desde la red de Compose.

## Pruebas de integración

Las pruebas usan el ejecutor incluido en Node.js 22, sin dependencias adicionales. Verifican la integración por HTTP a través de la UI con servicios, PostgreSQL y Redis reales.

| Caso | Comprobaciones |
| --- | --- |
| Catálogo y carrito | Consultar un producto, agregarlo, recuperar cantidad y precio, eliminarlo y comprobar que desaparece. |
| Compra y orden | Preparar y confirmar la compra, recuperar la orden desde Orders con sus artículos y dirección, comprobar importes de Checkout, eliminación de sesión y vaciado del carrito. |

Con `app/.env` preparado, ejecutar desde la raíz:

```powershell
docker compose --env-file app/.env -p tero-integration -f app/docker-compose.yml -f app/tests/integration/compose.yml up --build --abort-on-container-exit --exit-code-from integration-tests --attach integration-tests integration-tests
$LASTEXITCODE
```

El resultado esperado es **2 pruebas aprobadas, 0 fallidas y código de salida 0**. No hace falta instalar Node.js en el host. El proyecto `tero-integration` tiene su propia base de datos y no publica puertos.

Las APIs tienen hasta 90 segundos para estar disponibles y cada petición tiene un límite de 10 segundos. Solo se reintentan lecturas de disponibilidad. Cada prueba utiliza un identificador único y limpia su carrito; el cliente de prueba vacía el carrito después de comprar, como hace la UI. La orden ficticia se conserva porque no existe una API de borrado. Un fallo previo a confirmar también puede dejar una sesión de Checkout.

Para consultar resultados y retirar los contenedores conservando los datos:

```powershell
docker compose --env-file app/.env -p tero-integration -f app/docker-compose.yml -f app/tests/integration/compose.yml logs --no-color integration-tests
docker compose --env-file app/.env -p tero-integration -f app/docker-compose.yml -f app/tests/integration/compose.yml down
```

Ante un fallo de arranque, consultar también los logs de `catalog`, `carts`, `checkout`, `orders` y `ui`. Estas pruebas no cubren Admin, interfaz visual, rendimiento ni durabilidad ante reinicios. El caso de compra selecciona `priority-mail` y comprueba envío de 10 e impuesto de 5 según el contrato actual.

### Ejecución en CI

El workflow `.github/workflows/ci.yml` ejecuta las pruebas en cada PR y cada push a `main`. Genera credenciales efímeras, construye los cinco servicios usados por los casos y ejecuta la suite con el mismo Compose. El job independiente de build sigue construyendo y escaneando las seis imágenes, incluida Admin.

El código de salida de las pruebas determina el resultado del job `Pruebas de integración`. La publicación en GHCR requiere que aprueben tanto `build` como `integration`; solo se publica desde `main`. Esta dependencia bloquea la publicación si fallan los tests. Para exigir el resultado antes del merge, agregar el check `Pruebas de integración` a los checks requeridos de la protección de `main`.

El artifact `integration-results` conserva durante 30 días el reporte `integration.tap` y los logs `compose.log`, incluso si fallan los tests. El entorno de CI y su volumen temporal se retiran al finalizar. Las credenciales no se incluyen en el artifact. Descargar la evidencia relevante para la entrega antes de que expire.

La seguridad aún tiene pendientes: Trivy SCA e imágenes están configurados como informativos (`exit-code: 0`) y excluyen hallazgos sin parche (`ignore-unfixed: true`). Los tests no completan el gate de seguridad ni el análisis de calidad de código.

### Resultados

El 11 de noviembre de 2026 se ejecutaron los dos casos sobre un entorno Compose local con una base nueva: **2 aprobados, 0 fallidos, código 0**, con una duración del ejecutor de 2,20 segundos, sin contar la construcción y el arranque de los contenedores. Se verificaron los datos del carrito, la recuperación de la orden y la eliminación de la sesión. Un control adicional con destino inaccesible produjo **2 fallos y código 1** mediante el mismo mecanismo `--exit-code-from`, confirmando la propagación del error. El workflow pasó la validación de actionlint; su ejecución en GitHub Actions queda pendiente del PR. Se recomienda conservar el artifact de esa ejecución como evidencia y completar los gates de seguridad y calidad antes de promover ambientes.

## Comprobaciones manuales

Con el entorno local iniciado, abrir <http://localhost:8080> en una ventana privada:

1. Agregar un producto y comprobar nombre, cantidad y precio. Recargar y verificar que persiste. Eliminarlo y comprobar que el carrito sigue vacío tras recargar.
2. Agregar un producto, pulsar **Comprar**, completar datos ficticios con un email identificable y confirmar una sola vez. Anotar el código de orden, localizarlo en **Mis órdenes** y comprobar producto, cantidad y total de artículos. Verificar que el carrito queda vacío y la orden sigue visible al recargar.

**Mis órdenes** lista todas las órdenes y muestra el total de artículos, sin impuestos ni envío: identificar la compra por código y email.

```powershell
docker compose --env-file app/.env -p tero-manual -f app/docker-compose.yml down
```
