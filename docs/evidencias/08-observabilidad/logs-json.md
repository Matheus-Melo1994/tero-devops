# Logs JSON de los servicios

Los seis servicios emiten una línea JSON por evento a stdout o stderr. El contrato común es `timestamp` (UTC), `service`, `level` y `message`. Los accesos HTTP agregan `method`, `route`, `status` y `duration_ms`; `request_id` se incluye solo si llega en `X-Request-ID` con 1 a 64 caracteres alfanuméricos, `_` o `-`. Los nombres de servicio son `ui`, `admin`, `catalog`, `orders`, `checkout` y `carts`.

Ejemplo de acceso (ruta parametrizada, sin valores de la petición):

```json
{"timestamp":"2026-11-17T00:53:25.455Z","service":"checkout","level":"info","message":"HTTP request","method":"GET","route":"/health","status":200,"duration_ms":7.89,"request_id":"log_probe_37"}
```

Los logs de acceso no incluyen query strings, cuerpos, cookies, tokens, direcciones IP, user agents ni IDs de clientes. Las consultas SQL de GORM no se imprimen; los errores de base de datos se registran con la operación y el tipo de error, sin valores de la consulta. El servidor de Carts adapta los logs de Uvicorn al mismo formato y emite su propio evento de acceso HTTP.

## Verificación local

El 16/11/2026 se construyeron las seis imágenes y se levantó un proyecto Compose aislado, sin puertos publicados y con credenciales efímeras. Los seis endpoints `/health` respondieron 200. Se comprobó el acceso de Admin (login inválido 401, login válido, listado, alta, edición y baja de producto). Las dos pruebas existentes de integración aprobaron: 2/2, código 0.

Tras esas pruebas se analizaron todas las líneas de cada contenedor: UI 28, Admin 8, Catalog 10, Orders 5, Checkout 21 y Carts 33. Todas eran JSON válido, tenían los campos comunes y no contenían las credenciales de prueba, el email de compra ni los IDs de cliente. Un producto inexistente devolvió 404 sin imprimir la consulta SQL. En una prueba controlada se detuvo Carts y UI devolvió 502; sus dos eventos de error fueron JSON válido y no incluyeron la URL ni sus parámetros. Luego se reinició Carts y los seis endpoints volvieron a responder 200.

Para inspeccionar el formato con Compose: `docker compose --env-file app/.env -f app/docker-compose.yml logs --no-log-prefix --no-color catalog orders ui admin checkout carts`. La centralización, retención y búsqueda en CloudWatch quedan para la configuración de ECS de la issue #37.
