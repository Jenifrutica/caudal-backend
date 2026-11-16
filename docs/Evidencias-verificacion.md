# Evidencias de verificación

> Registro de lo que se ejecutó para respaldar cada afirmación de [`Drivers.md`](Drivers.md), [`ADRs/`](ADRs/README.md), [`Trazabilidad-arquitectura.md`](Trazabilidad-arquitectura.md) y [`Arranque-local.md`](Arranque-local.md). Si una verificación falla, su fila **se queda** con el fallo y el bloqueo; no se borra. No contiene tokens, cookies ni contraseñas.

## 1. Fecha, versiones y entorno

| Dato | Valor |
|---|---|
| Fecha | 2026-11-16 |
| Base | `develop` de cada fork: backend `3c87ae3`, frontend `c0e474c`, ia `0b153ae`, simulador `521048a`, más los cambios de la rama `docs/arquitectura-5-5` |
| Sistema | Fedora 44, Linux 7.3.3 (x86_64), con SELinux activo |
| Docker | Engine 29.9.2, Compose 5.6.0 |
| Java | OpenJDK 25.0.5 (`/usr/lib/jvm/java-25-openjdk`; el JDK por defecto de la máquina es el 21, así que se exportó `JAVA_HOME`) |
| Node / pnpm | Node 24.19.0 / pnpm 12.6.0 (vía `corepack`, según `packageManager`) |
| Python | 3.12 en el contenedor `ghcr.io/astral-sh/uv:0.9.7-python3.12-bookworm-slim` (la máquina tiene 3.14 y no tiene `uv`) |

## 2. Resultados

| # | Verificación | Comando | Resultado | Evidencia |
|---|---|---|---|---|
| 1 | El backend compila con JDK 25 | `JAVA_HOME=/usr/lib/jvm/java-25-openjdk ./mvnw -q -DskipTests compile` | **OK** (exit 0, 32 s) | Sin errores |
| 2 | La estructura cumple el hexágono (D-08, ADR-001) | `./mvnw -q -Dtest=ArchitectureTest -Dsurefire.failIfNoSpecifiedTests=false test` | **OK**: 11 pruebas, 0 fallos | `TEST-co.caudal.architecture.ArchitectureTest.xml`: `tests=11 failures=0` |
| 3 | Pruebas unitarias citadas en los ADR (D-04, D-05, D-09, D-13, D-14) | `./mvnw -q -Dtest='RemoteForecasterProxyTest,CircuitBreakerStateTest,ShadowBaselineForecasterTest,RefreshCookieTest,RefreshTokenServiceTest,RefreshTokenStateTest,PublicScheduleProxyTest,DeviceTelemetryAdapterTest,NaivePersistenceStrategyTest' test` | **OK**: 9 suites, 47 pruebas, 0 fallos | RemoteForecasterProxy 5, CircuitBreakerState 4, ShadowBaseline 2, RefreshCookie 6, RefreshTokenService 10, RefreshTokenState 7, PublicScheduleProxy 2, DeviceTelemetryAdapter 7, NaivePersistenceStrategy 4 |
| 4 | Pruebas de integración con PostgreSQL 18 real (D-01, D-02, D-03, D-15) | `./mvnw -B -ntp verify -Dtest=NONE -Dsurefire.failIfNoSpecifiedTests=false -Dit.test='AqueductIsolationIT,AppendOnlyAndTriggersIT,ImportIT,ReadingBatchIT,EndpointAuthorizationIT,AuditTrailIT'` (con Checkstyle, SpotBugs, Spotless y JaCoCo omitidos para acotar) | **OK**: 26 pruebas, 0 fallos, `BUILD SUCCESS` (1 min 34 s) | AqueductIsolationIT 3, AppendOnlyAndTriggersIT 12, ImportIT 4, ReadingBatchIT 3, EndpointAuthorizationIT 3, AuditTrailIT 1 |
| 5 | Formato del backend | `./mvnw -q spotless:check` | **OK** (exit 0) | — |
| 6 | La PWA instala y compila | `corepack pnpm install --frozen-lockfile && corepack pnpm build` | **OK** (exit 0, 51 s) | `✓ built`; PWA con `generateSW`, 16 entradas en precaché |
| 7 | Formato y lint de la PWA con los cambios | `corepack pnpm format:check && corepack pnpm lint` | **OK** | "All matched files use Prettier code style!"; ESLint sin errores |
| 8 | Cola offline (D-01, ADR-007) | `corepack pnpm vitest run src/core/commands/CommandQueue.test.ts src/test/integration/offlineReadings.test.ts` | **OK**: 2 archivos, 22 pruebas | — |
| 9 | Pruebas y lint de la IA | `uv sync --frozen && uv run pytest -q && uv run ruff check .` (en el contenedor de Python 3.12) | **OK**: 177 pruebas (3 deseleccionadas: marca `chronos`, que descarga pesos), ruff "All checks passed!" | — |
| 10 | Pruebas y lint del simulador | `uv sync --frozen && uv run pytest -q && uv run ruff check .` (ídem) | **OK**: 373 pruebas, ruff "All checks passed!" | — |
| 11 | Un comando levanta el sistema completo, desde cero | `make reset-db && rm -f .env && DB_HOST_PORT=55432 make up` | **OK**: `caudal-db`, `caudal-api`, `caudal-ia` y `caudal-web` *healthy* en 32 s (imágenes ya construidas) | Salida en §3. El primer `make up`, con build completo y descargas, tardó **7 min 22 s** |
| 12 | Prueba de humo | `make smoke` | **OK**: 9 de 9, exit 0 | Salida en §3 |
| 13 | La API local corre con el rol sin privilegios (D-03, ADR-002) | `SELECT usename, count(*) FROM pg_stat_activity …` y atributos de `pg_roles` | **OK**: el pool usa `caudal_app` (10 conexiones); `caudal_app` con `rolsuper = f` y `rolbypassrls = f`; 53 migraciones aplicadas | — |
| 14 | RLS en la base local (D-03) | Como `caudal_app` sin `app.aqueduct_id`: `SELECT count(*) FROM org.tanks` | **OK**: 0 filas (hay 1 tanque, que el dueño sí ve) | `org.aqueducts` no tiene RLS a propósito (es el registro de acueductos que resuelve el *slug* público); `org.tanks` y `ops.readings` sí tienen `relforcerowsecurity = t` |
| 15 | *Append-only* en la base local (D-02) | Como `caudal_app`: `UPDATE ops.readings SET gauge_value = 0` | **OK**: `ERROR: permission denied for table readings` | — |
| 16 | Consulta autenticada con datos (no solo salud) | `scripts/demo-admin.sh junta.demo "Junta Demo"` (contraseña aleatoria, borrada al terminar) → `POST /api/v1/auth/login` → `GET /api/v1/rule-sets/current` con Bearer | **OK**: login 200 (`role: BOARD_ADMIN`, `must_change_password: true`, `expires_in: 900`); reglas vigentes 200 con válvulas, ventana 05:00–21:00 y regla 0,00–5,00 | El hash Argon2id generado con `argon2-cffi` lo verifica `Argon2PasswordHasherAdapter` sin cambios |
| 17 | API en producción | `curl https://caudal-api-7crk.onrender.com/actuator/health` y `/v3/api-docs`, `/api/v1/meta/constraints` | **OK** después del arranque en frío: health 200 `UP`, api-docs 200 (39 s), constraints 200 | Las dos primeras llamadas agotaron 90 s mientras Render despertaba el servicio (RG-04) |
| 18 | IA en producción | `curl https://caudal-ia.onrender.com/v1/health` y `/v1/ready` | **OK**: 200 `{"status":"ok"}` (94 s, arranque en frío) y 200 `{"status":"ready","model_loaded":true}` | — |
| 19 | PWA en producción | `curl https://caudal-frontend.vercel.app/` | **OK**: 200 en 0,7 s, `<html lang="es">` | — |
| 20 | Página pública del acueducto demo en producción | `curl https://caudal-api-7crk.onrender.com/api/v1/public/vereda-demo/schedule` | **404 `NOT_FOUND`** (esperado) | No hay horario publicado para hoy. Por decisión de la dueña del fork **no se tocó producción**; los pasos para publicarlo antes de la sustentación están en [`Arranque-local.md`](Arranque-local.md) §6 |
| 21 | Rutas citadas en la trazabilidad y los ADR existen | Script que extrae cada ruta entre comillas invertidas y comprueba que exista | **OK**: 0 faltantes (1 falso positivo: una ruta del frontend citada sin prefijo) | — |
| 22 | Sin marcas "verificar/por definir" sin dueño | `grep -nE 'verificar\|por definir' docs/Arquitectura.md` y en `caudal-frontend/.agents/architecture.md` | **OK**: 0 en ambos (había 12 líneas y 6 líneas). Los pendientes reales quedaron con dueño y revisión | — |
| 23 | Sin secretos en los cambios | `gitleaks dir` (imagen `zricethezav/gitleaks:v8.21.2`, con `.gitleaks.toml` del backend) sobre los 30 archivos nuevos o modificados de los cuatro repositorios | **OK**: "no leaks found" | `.env` y `target/` siguen ignorados (`git status --ignored`) |

## 3. Salida del arranque desde cero

```text
$ make reset-db
 Volume caudal_caudal-db-data Removed
$ rm -f .env
$ DB_HOST_PORT=55432 make up
 Container caudal-db Healthy
 Container caudal-ia Healthy
 Container caudal-api Healthy
 Container caudal-web Healthy
PWA http://localhost:8081  API http://localhost:8080/swagger-ui.html  IA http://localhost:8000/docs
real	0m31,694s
$ make smoke
OK    API /actuator/health                     200, contiene "status":"UP"
OK    API /v3/api-docs                         200, contiene "openapi"
OK    API datos: /api/v1/meta/constraints      200, contiene "password"
OK    API sin token: /api/v1/readings          HTTP 401
OK    API acueducto ajeno: /public/schedule    HTTP 404
OK    IA /v1/health                            200, contiene ok
OK    IA sin token: POST /v1/forecasts         HTTP 401
OK    PWA /                                    200, contiene <title>CAUDAL
OK    PWA fallback SPA /a/vereda-demo          200, contiene <title>CAUDAL

smoke: todas las verificaciones pasaron (full).
$ make ps
NAME         IMAGE              SERVICE   STATUS                    PORTS
caudal-api   caudal-api:local   api       Up 12 seconds (healthy)   127.0.0.1:8080->10000/tcp
caudal-db    postgres:18        db        Up 18 seconds (healthy)   127.0.0.1:55432->5432/tcp
caudal-ia    caudal-ia:local    ia        Up 18 seconds (healthy)   127.0.0.1:8000->7860/tcp
caudal-web   caudal-web:local   web       Up 12 seconds (healthy)   127.0.0.1:8081->8080/tcp
```

Se quitaron las líneas de progreso del build y algunas columnas de `make ps`; el resto es la salida literal.

## 4. Fallos encontrados durante la verificación (y cómo se resolvieron)

| Fallo | Causa | Resolución |
|---|---|---|
| El primer `make up` se detuvo en `make env` con "quedaron marcadores sin reemplazar", y `make smoke` falló 9 de 9 | La comprobación de `cambia-esto-` también contaba las líneas de comentario de `.env.example` | `scripts/dev-env.sh` ahora ignora los comentarios. Esto también demostró que `make smoke` sale con código distinto de 0 cuando nada responde |
| `caudal-db` se reiniciaba con `ls: cannot open directory '/docker-entrypoint-initdb.d/': Permission denied` | SELinux de Fedora bloquea el montaje de `docker/db-init` | Montaje con `:ro,z` en `docker-compose.yml` |
| `make smoke` falló 1 de 9 en `/meta/constraints` | La prueba esperaba un envoltorio `fields` que la API no tiene (el mismo error estaba en la guía del frontend) | La prueba busca un campo real (`password`) y se corrigió `caudal-frontend/.agents/architecture.md` §7.2 |
| Las pruebas de Python no podían leer el repositorio montado | SELinux, igual que arriba | `docker run --security-opt label=disable` (solo para la verificación, sin cambiar etiquetas de archivos) |

## 5. No verificado en este entorno

| Qué | Por qué | Siguiente paso |
|---|---|---|
| `./mvnw verify` completo (todas las pruebas, JaCoCo, Checkstyle y SpotBugs) | Se ejecutaron las pruebas citadas en los documentos, no la suite entera, para acotar el tiempo | Lo corre el workflow `ci` en el PR |
| Playwright con axe (`e2e/accessibility.spec.ts`, D-11) | Requiere instalar los navegadores de Playwright | `pnpm e2e:install && pnpm e2e` |
| Perfil `sim` levantado contra la API local | Necesita las credenciales del simulador, que crea la Junta (no hay cuentas sembradas) | `scripts/demo-admin.sh`, crear las cuentas del simulador y `docker compose --profile sim up -d sim` |
| Horario publicado en producción | Decisión de no tocar producción en este trabajo | Seguir [`Arranque-local.md`](Arranque-local.md) §6 antes de la sustentación |
