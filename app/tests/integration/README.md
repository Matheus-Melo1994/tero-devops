# Pruebas de integración

Dos casos que verifican la integración por HTTP a través de la UI, con servicios, PostgreSQL y Redis reales. Usan el ejecutor incluido en Node.js 22, sin dependencias adicionales.

| Caso | Comprobaciones |
| --- | --- |
| Catálogo y carrito | Consultar un producto, agregarlo, recuperar cantidad y precio, eliminarlo y comprobar que desaparece. |
| Compra y orden | Preparar y confirmar la compra, recuperar la orden desde Orders con sus artículos y dirección, comprobar importes de Checkout, eliminación de sesión y vaciado del carrito. |

## Ejecución local

Con `app/.env` preparado, desde la raíz del repositorio:

```bash
docker compose --env-file app/.env -p tero-integration \
  -f app/docker-compose.yml -f app/tests/integration/compose.yml \
  up --build --abort-on-container-exit --exit-code-from integration-tests \
  --attach integration-tests integration-tests
echo "exit: $?"
```

Resultado esperado: **2 pruebas aprobadas, 0 fallidas, código de salida 0**. No hace falta instalar Node.js en el host. El proyecto `tero-integration` tiene su propia base de datos y no publica puertos.

Las APIs tienen hasta 90 segundos para estar disponibles y cada petición tiene un límite de 10 segundos. Solo se reintentan lecturas de disponibilidad. Cada prueba usa un identificador único y limpia su carrito; el cliente de prueba vacía el carrito después de comprar, como hace la UI. La orden ficticia se conserva porque no existe una API de borrado. Un fallo previo a confirmar también puede dejar una sesión de Checkout.

Para consultar resultados y retirar los contenedores conservando los datos:

```bash
docker compose --env-file app/.env -p tero-integration -f app/docker-compose.yml -f app/tests/integration/compose.yml logs --no-color integration-tests
docker compose --env-file app/.env -p tero-integration -f app/docker-compose.yml -f app/tests/integration/compose.yml down
```

Ante un fallo de arranque, consultar también los logs de `catalog`, `carts`, `checkout`, `orders` y `ui`.

## Alcance

Estas pruebas no cubren Admin, interfaz visual, rendimiento ni durabilidad ante reinicios. El caso de compra selecciona `priority-mail` y comprueba envío de 10 e impuesto de 5 según el contrato actual.

## Ejecución en CI

El job `Pruebas de integración` de `.github/workflows/ci.yml` corre en cada PR y cada push a `main`. Genera credenciales efímeras, construye los cinco servicios usados por los casos y ejecuta la suite con el mismo Compose. El job de build sigue construyendo y escaneando las seis imágenes, incluida Admin.

El código de salida de las pruebas determina el resultado del job. La publicación en GHCR requiere que aprueben tanto `build` como `integration`; solo se publica desde `main`.

El artifact `integration-results` conserva durante 30 días el reporte `integration.tap` y los logs `compose.log`, incluso si fallan los tests. Las credenciales no se incluyen en el artifact.

## Resultados

El 11 de noviembre de 2026 se ejecutaron los dos casos sobre un entorno Compose local con una base nueva: **2 aprobados, 0 fallidos, código 0**, con una duración del ejecutor de 2,20 segundos, sin contar construcción y arranque de contenedores. Un control adicional con destino inaccesible produjo **2 fallos y código 1** mediante el mismo mecanismo `--exit-code-from`, confirmando la propagación del error. El workflow pasó la validación de actionlint y su primera ejecución en GitHub Actions (PR #55) fue exitosa.

## Comprobaciones manuales

Con el entorno local iniciado, abrir <http://localhost:8080> en una ventana privada:

1. Agregar un producto y comprobar nombre, cantidad y precio. Recargar y verificar que persiste. Eliminarlo y comprobar que el carrito sigue vacío tras recargar.
2. Agregar un producto, pulsar **Comprar**, completar datos ficticios con un email identificable y confirmar una sola vez. Anotar el código de orden, localizarlo en **Mis órdenes** y comprobar producto, cantidad y total de artículos. Verificar que el carrito queda vacío y la orden sigue visible al recargar.

**Mis órdenes** lista todas las órdenes y muestra el total de artículos, sin impuestos ni envío: identificar la compra por código y email.
