# Informe de análisis estático y calidad

Estado al 24/11/2026, rama `main`, SonarCloud (`devops-ort-2/tero-devops`, 3.3k líneas) con el quality
gate "Sonar way". Complementa el informe de seguridad de dependencias e imágenes (Trivy) que está en el
[README raíz, sección "Remediación de vulnerabilidades"](../README.md#remediación-de-vulnerabilidades-issue-59).

## 1. Resumen

| Indicador | Estado |
|---|---|
| Quality gate | **Passed** (bloqueante en el pipeline: el job `quality` espera el resultado y falla si no aprueba) |
| Issues abiertos | 69 (9 seguridad, 40 confiabilidad, 36 mantenibilidad) |
| Security hotspots | 0, rating A |
| Duplicación | 0,0 % (excluidos los 4 loggers, ver ADR-06) |
| Cobertura | no se mide (ADR-07) |
| Cerrados en los últimos 30 días | 7 (4 seguridad, 1 confiabilidad, 2 mantenibilidad) |
| Ratings | Seguridad C · Confiabilidad C · Mantenibilidad A · Revisión de seguridad A |

Punto de partida: el primer análisis (12/11/2026) encontró 89 issues. Con el gate bloqueando desde
entonces, ningún PR entró con issues nuevos; los 69 que quedan son deuda heredada del código original de
Tero.

## 2. Hallazgos significativos

### 2.1 Seguridad (9 issues: 3 medium, 6 low)

Ninguno es una vulnerabilidad explotable en el despliegue actual. Los más relevantes que se encontraron
y cómo se trataron:

- **Dependencias de Python sin verificación de hashes** (`docker:S8544`, `app/src/cart/Dockerfile`).
  Detectado por el gate en el PR #62. **Corregido**: `requirements.txt` generado con
  `pip-compile --generate-hashes` e instalación con `--require-hashes`.
- **Escucha en `0.0.0.0`** (`S8392`) en los servicios. **Aceptado con justificación**: dentro de un
  contenedor es la forma correcta de escuchar; la exposición la controla el security group y el ALB,
  no el bind del proceso.
- **`except` que oculta la traza** (`S8572`, `cart`). **Corregido**: `logger.exception`.
- Los 9 restantes son medium/low sobre cabeceras y configuración de Express en `ui` y `admin`
  (helmet, cookies, CORS). Ver recomendaciones.

### 2.2 Confiabilidad (40 issues, rating C)

| Regla | Cant. | Dónde | Impacto real |
|---|---|---|---|
| (HTML) `input`/`select`/`textarea` deben tener una etiqueta asociada | 12 | `admin/public/index.html` | Accesibilidad del panel admin; no afecta el funcionamiento |
| (HTML) Los `label` deben tener texto accesible | 12 | `admin/public/index.html` | Ídem |
| (JS) Usar `replaceAll` en lugar de `replace` con regex global | 6 | `admin/public/*.js` | Legibilidad; sin cambio de comportamiento |
| (JS) Aserciones fuera de lugar | 3 | tests | Solo tests |
| (TS/JS) Usar `Number.parseInt`/`Number.isNaN` en lugar de los globales | 5 | `ui`, `admin` | Legibilidad |
| (Go) Reutilizar el `context` recibido en lugar de crear uno nuevo | 1 | `catalog` | Cancelaciones no se propagan; menor |
| (TS) Funciones `async` sin `await` / promesas sin manejar | 2 | `checkout` | Un error en esa promesa no se registraría |

Lectura: 24 de las 40 son accesibilidad de un único archivo HTML estático del panel de administración.
El rating C viene del volumen, no de la gravedad. Las dos que sí valen la pena corregir primero son las
promesas sin manejar en `checkout` y el contexto en `catalog`.

### 2.3 Mantenibilidad (36 issues, rating A)

Code smells menores (nombres, funciones largas, `console.log`, comentarios). Rating A: no requieren
acción inmediata.

## 3. Decisiones tomadas sobre el gate

- Se usa "Sonar way" sin modificar (plan gratuito, no permite gates propios) y con
  `sonar.qualitygate.wait=true`, así el pipeline falla cuando el gate falla.
- Se excluyó la **cobertura** (`sonar.coverage.exclusions`): Tero no trae tests unitarios y agregarlos a
  seis servicios quedó fuera de alcance. La calidad funcional se cubre con las pruebas de integración
  del pipeline (ADR-07).
- Se excluyeron de **duplicación** los cuatro loggers (uno por lenguaje) que implementan el mismo
  contrato de logs JSON (ADR-06).
- Las reglas no se desactivaron en ningún caso. `S8392` se marcó como *Accepted* en SonarCloud con el
  motivo escrito.

## 4. Recomendaciones accionables

Ordenadas por relación valor/esfuerzo. Las dos primeras son las únicas con impacto en producción.

1. **`checkout`: manejar las promesas sueltas** (2 issues, ~15 min). Agregar `await` o `.catch` con log
   de error; hoy un fallo ahí no deja rastro en los logs JSON y la alarma `application-errors` no lo
   vería.
2. **`catalog`: reutilizar el `context` de la petición** (1 issue, ~10 min). Pasar el `ctx` del handler
   a las consultas de GORM para que una petición cancelada no siga consumiendo la base.
3. **`ui`/`admin`: cabeceras de seguridad en Express** (los 9 de seguridad, ~1 h). Agregar `helmet`,
   marcar las cookies de sesión de `admin` como `HttpOnly`/`SameSite` y restringir CORS a los orígenes
   del ALB. Bajaría el rating de seguridad de C a A.
4. **`admin/public/index.html`: accesibilidad** (24 issues, ~2 h). Asociar cada `label` a su `input`
   con `for`/`id`. Es mecánico y baja confiabilidad de C a A, pero no cambia el comportamiento.
5. **`replace` → `replaceAll` y `Number.*`** (11 issues, ~30 min). Cambios de una línea; se pueden
   hacer en el mismo PR que el punto 4.
6. **Medir cobertura** cuando haya tests unitarios: quitar `sonar.coverage.exclusions` y fijar un
   umbral realista (por ejemplo 40 % en código nuevo) antes de subirlo.

Los puntos 1 a 3 son candidatos a un PR `fix/sonar-reliability-security` después de la entrega; los
demás quedan documentados como deuda conocida.

## 5. Evidencia

- `docs/evidencias/04-testing/sonar-primer-analisis.png`: primer análisis, 89 issues.
- `docs/evidencias/04-testing/sonar-quality-gate-asignado.png`: gate "Sonar way" asignado.
- `docs/evidencias/04-testing/sonar-overview-2026-11-24.png`: estado actual (gate Passed, 69 issues).
- `docs/evidencias/04-testing/sonar-reliability-rules-2026-11-24.png`: reglas de confiabilidad.
- `sonar-project.properties`: exclusiones vigentes.
