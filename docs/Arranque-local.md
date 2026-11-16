# Arranque local con un comando

> Levanta CAUDAL completo en la máquina, con la misma forma del diagrama de contenedores ([`Arquitectura.md`](Arquitectura.md) §1.2): **PostgreSQL 18 + API Java + servicio de IA + PWA**, y el simulador como opción. Lo usa el evaluador para comprobar que el esqueleto corre y corresponde al diseño. Evidencia de la última ejecución: [`Evidencias-verificacion.md`](Evidencias-verificacion.md).

## 1. Requisitos

| Herramienta | Versión probada | Para qué |
|---|---|---|
| Docker Engine con Compose v2 | 29.9.2 | Todo el arranque (`make up`) |
| GNU Make, `curl`, `openssl` | las del sistema | `make`, la prueba de humo y la generación de secretos |
| JDK 25 | Temurin/OpenJDK 25.0.5 | Solo para correr la API o las pruebas fuera de Docker |
| Node 24 + pnpm 12 (vía `corepack`) | Node 24.19, pnpm 12.6.0 | Solo para desarrollar la PWA fuera de Docker |
| `uv` + Python 3.12 | uv 0.9 | Solo para la IA o el simulador fuera de Docker |

Recursos medidos el 2026-11-16 (`docker image ls` y `docker stats`): imágenes de unos **4,6 GB** en total (`caudal-ia` 3,2 GB porque trae PyTorch y `chronos-bolt-tiny` horneado; `caudal-api` 631 MB; `postgres:18` 647 MB; `caudal-web` 88 MB) y unos **930 MiB de RAM** con todo en reposo (API 541 MiB, IA 313 MiB, db 59 MiB, web 14 MiB).

## 2. Carpetas

Los cuatro repositorios van como **carpetas hermanas**: `docker-compose.yml` construye la IA, la PWA y el simulador desde `../caudal-ia`, `../caudal-frontend` y `../caudal-simulador`.

```bash
mkdir caudal && cd caudal
for r in caudal-backend caudal-frontend caudal-ia caudal-simulador; do
  git clone -b develop "https://github.com/Jenifrutica/$r.git"
done
cd caudal-backend
```

## 3. Comandos

```bash
make up       # crea .env si falta, construye y levanta db + api + ia + web, y espera a que estén sanos
make smoke    # verifica API, IA y PWA; termina con código distinto de 0 si algo falla
```

| Comando | Qué hace |
|---|---|
| `make env` | Crea `.env` desde `.env.example` con secretos aleatorios (`openssl rand -base64 32`). No imprime los secretos y no sobrescribe un `.env` existente. |
| `make up` | `docker compose --profile full up -d --build --wait`: db, api, ia y web. |
| `make up-core` | Solo db y api, sin construir la imagen de la IA. |
| `make smoke` | 9 verificaciones (salud, OpenAPI, datos, 401 sin token, 404 de otro acueducto, IA, PWA y fallback SPA). |
| `make smoke-core` | Solo las 5 de la API. |
| `make ps` / `make logs` | Estado y logs. |
| `make down` | Detiene todo y conserva los datos. |
| `make reset-db` | Detiene todo y **borra** el volumen de PostgreSQL. |
| `docker compose --profile sim up -d sim` | Agrega el tablero del simulador (necesita las credenciales del simulador en su `.env`, ver `caudal-simulador/README.md`). |

`docker compose up -d db` sigue funcionando igual que antes, para quien solo quiere la base y corre la API con `./mvnw spring-boot:run`.

## 4. Puertos

Todos se publican solo en `127.0.0.1`.

| Servicio | URL en la máquina | Puerto interno | Imagen |
|---|---|---|---|
| PWA (`web`) | http://localhost:8081 | 8080 (nginx sin privilegios) | `caudal-frontend/Dockerfile` |
| API (`api`) | http://localhost:8080 · Swagger en `/swagger-ui.html` | 10000 | `caudal-backend/Dockerfile` |
| IA (`ia`) | http://localhost:8000 · `/v1/health`, `/docs` | 7860 | `caudal-ia/Dockerfile` |
| PostgreSQL (`db`) | `localhost:${DB_HOST_PORT:-5432}` | 5432 | `postgres:18` |
| Simulador (`sim`, opcional) | http://localhost:8090 | 8000 | `caudal-simulador/Dockerfile` |

Si el puerto 5432 ya está ocupado (por ejemplo, por otro PostgreSQL), genera el `.env` con otro puerto: `rm .env && DB_HOST_PORT=55432 make up`.

## 5. Qué es solo de desarrollo

Nada de esto se usa en producción (Render, Neon y Vercel tienen sus propias variables):

- `sslmode=disable` contra el contenedor `db`. En Neon se usa `verify-full`.
- `COOKIE_SECURE=false` y `COOKIE_SAME_SITE=Lax`, porque en local no hay HTTPS y la PWA y la API son el mismo sitio (`localhost`). En producción son `true` y `None` ([ADR-005](ADRs/ADR-005-refresh-en-cookie-httponly.md)).
- `CORS_ALLOWED_ORIGINS=http://localhost:8081,http://localhost:5173`.
- El rol `caudal_app` recibe la contraseña de `DATABASE_PASSWORD` mediante `docker/db-init/10-app-role.sh`, que corre una sola vez con el volumen vacío. Así la API local se conecta **como `caudal_app`**, sin superusuario ni `BYPASSRLS`, y la RLS se aplica igual que en producción ([ADR-002](ADRs/ADR-002-aislamiento-con-rls.md)). `caudal_migrator` (dueño del esquema) solo lo usa Flyway.
- Los secretos de `.env` son aleatorios y locales. `.env` está en `.gitignore`.

## 6. Demo de punta a punta (página pública)

El backend **no siembra cuentas** a propósito: la migración `V47__seed_demo_aqueduct.sql` crea el acueducto `vereda-demo` con datos simulados y una cuenta de sistema deshabilitada. Para entrar a la PWA local:

1. Crea la primera cuenta de la Junta del acueducto demo (pide la contraseña por teclado y no la muestra):

   ```bash
   scripts/demo-admin.sh junta.demo "Junta Demo"
   ```

   La cuenta queda como `BOARD_ADMIN` de `vereda-demo` y debe cambiar la contraseña en el primer ingreso (HU-02).
2. Entra en http://localhost:8081, cambia la contraseña y acepta el aviso de privacidad.
3. Desde el panel de la Junta crea las demás cuentas (fontanero, equipo) con `POST /api/v1/users` y `POST /api/v1/memberships`.
4. Para que `/a/vereda-demo` muestre el horario de hoy:
   1. el fontanero registra una lectura;
   2. la Junta genera la propuesta (`POST /api/v1/schedule-proposals`);
   3. la aprueba (`…/{id}/approve`);
   4. la publica (`…/{id}/publish`).

   Mientras no haya un horario publicado para la fecha, la página pública responde 404 a propósito.
5. **Antes de la sustentación, en producción:** la misma secuencia con las cuentas reales de la Junta demo. El repositorio no guarda credenciales; quien presenta las lleva.

## 7. Solución de problemas

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `make env` termina con "quedaron marcadores sin reemplazar" | `.env.example` tiene una variable nueva con `cambia-esto-` | Agrégala a `scripts/dev-env.sh` y repite. |
| `caudal-db` en reinicio con `Permission denied` sobre `/docker-entrypoint-initdb.d/` | SELinux (Fedora o RHEL) bloquea el montaje | El montaje ya usa `:z`. Si cambiaste el compose, vuelve a ponerlo. |
| `bind: address already in use` en 5432 | Otro PostgreSQL local | `rm .env && DB_HOST_PORT=55432 make up` |
| La API no arranca: `password authentication failed for user "caudal_app"` | El volumen se creó antes de existir `.env` o con otro `.env` | `make reset-db && make up` (borra los datos locales). |
| El primer `make up` tarda varios minutos | Descarga de imágenes base y dependencias de Maven, pnpm y PyTorch | Normal. Las siguientes veces usa la caché de capas. Para iterar en la API, `make up-core`. |
| La PWA abre pero no inicia sesión | Origen distinto de `http://localhost:8081` (CORS) | Usa exactamente esa URL, o agrega el origen a `CORS_ALLOWED_ORIGINS`. |

## 8. Limpieza

```bash
make reset-db                      # contenedores y volumen de datos
docker image rm caudal-api:local caudal-ia:local caudal-web:local caudal-sim:local
rm .env                            # secretos locales
```

## 9. Por qué así (y no un repositorio de orquestación)

El `docker-compose.yml` y el `Makefile` viven en `caudal-backend`, que ya es el repositorio de la documentación canónica y el que tenía el compose de PostgreSQL. La alternativa de un quinto repositorio `caudal-platform` solo con el compose se descartó: suma un repositorio más que mantener y versionar para un equipo de 3 personas (D-06 en [`Drivers.md`](Drivers.md)), y no aporta aislamiento, porque igual necesita los cuatro repositorios como hermanos.
