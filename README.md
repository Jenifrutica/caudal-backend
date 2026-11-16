# CAUDAL Backend

API REST de **CAUDAL**, el cuaderno digital del acueducto veredal: reglas versionadas de la Junta, lecturas validadas del tanque, pronóstico con IA y respaldo simple, propuesta de turnos explicada, aprobación de la Junta, publicación sin datos personales, cierre del día y actas.

Java 25 · Spring Boot 4.1 · PostgreSQL 18 · Swagger.

![Contexto](docs/images/c4-contexto.png)

## Estado

**Fases 1 a 12 completas** (estado de `develop` verificado el 2026-11-16 en `3c87ae3`): login con MFA, reglas versionadas, lecturas con validación en cadena e importación simulada, pronóstico con respaldo, turnos y decisión de la Junta, publicación, reportes de daño, cierre y actas, evaluación de la IA, dispositivos firmados con Ed25519 y endurecimiento. Detalle y pendientes en [Versión 1.0.0](docs/Version-1.0.0.md). La etiqueta `v1.0.0` todavía **no** está creada (paso 4 de esa página).

En cifras: 792 archivos Java de producción, 198 de prueba, 34 controladores, 56 puertos de salida y 53 migraciones Flyway (7 esquemas, 57 tablas). Desplegado en Render: `https://caudal-api-7crk.onrender.com` (`/actuator/health`, `/swagger-ui.html`).

## Arranque rápido (sistema completo)

Con los cuatro repositorios clonados como carpetas hermanas (`caudal-backend`, `caudal-frontend`, `caudal-ia`, `caudal-simulador`) y Docker con Compose:

```bash
make up       # PostgreSQL 18 + API + IA + PWA, con .env generado y secretos aleatorios
make smoke    # 9 verificaciones; termina con código distinto de 0 si algo falla
```

| Pieza | URL |
|---|---|
| PWA | http://localhost:8081 |
| API y Swagger | http://localhost:8080/swagger-ui.html |
| IA | http://localhost:8000/v1/health |
| PostgreSQL | `localhost:5432` (configurable con `DB_HOST_PORT`) |

Guía completa, puertos, solución de problemas y demo: [Arranque local](docs/Arranque-local.md). Evidencia de la última ejecución: [Evidencias de verificación](docs/Evidencias-verificacion.md).

## Arquitectura

La documentación de este repositorio es la **canónica** de los cuatro. Para la arquitectura, la ruta de lectura es:

1. [Drivers y árbol de utilidad](docs/Drivers.md): qué fuerzas moldean el diseño y cómo se priorizaron.
2. [Decisiones (ADR-001 a ADR-007)](docs/ADRs/README.md): cada decisión con sus alternativas descartadas.
3. [Trazabilidad](docs/Trazabilidad-arquitectura.md): driver → ADR → clase real → prueba → comando.
4. [Arquitectura](docs/Arquitectura.md): C4, hexágono, flujos, despliegue y CI/CD.

## Versiones fijadas

| Componente | Versión |
|---|---|
| Java (JDK) | 25 LTS (Temurin) |
| Maven (Wrapper) | 3.9.16 |
| Spring Boot | 4.1.1 |
| springdoc-openapi | 3.1.1 |
| PostgreSQL | 18 (imagen `postgres:18`) |

## Documentación

- [Índice de la documentación](docs/README.md): drivers, ADR, trazabilidad, problema, actores, historias de usuario, requerimientos, reglas de negocio, arquitectura, modelo de datos, API, seguridad, patrones, IA, datos simulados, hardware, planeación y plan de commits.
- [AGENTS.md](AGENTS.md): reglas obligatorias para personas y agentes.
- [Flujo de trabajo](.agents/workflow.md): cuentas, ramas, commits y PR.
- [Política de seguridad](SECURITY.md) y [cómo contribuir](CONTRIBUTING.md).

## Cómo correr solo la API fuera de Docker

Requisitos: JDK 25 y Docker Engine con Compose. Con Podman funciona igual si `DOCKER_HOST` apunta a su socket (`systemctl --user start podman.socket` y `export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock`).

1. Prepara las variables. Spring no lee `.env` por su cuenta, así que se exportan en la terminal:

   ```bash
   cp .env.example .env      # reemplaza cada "cambia-esto-..." por un valor local
   set -a; . ./.env; set +a
   ```

   Más simple: `make env` genera el `.env` local con `DATABASE_URL` y `FLYWAY_URL` apuntando a `localhost` y con secretos aleatorios. La API se conecta como `caudal_app` (el contenedor `db` le asigna la contraseña de `DATABASE_PASSWORD` al crearse el volumen) y Flyway migra como `caudal_migrator`.

2. Levanta PostgreSQL 18:

   ```bash
   docker compose up -d db
   docker compose ps         # el servicio db debe quedar "healthy"
   ```

3. Ejecuta la API:

   ```bash
   ./mvnw spring-boot:run
   ```

4. Comprueba que responde:

   ```bash
   curl http://localhost:8080/actuator/health      # {"status":"UP", ...}
   ```

### Rutas de documentación

| Ruta | Contenido |
|---|---|
| `http://localhost:8080/swagger-ui.html` | Swagger UI (redirige a `/swagger-ui/index.html`) |
| `http://localhost:8080/v3/api-docs` | Documento OpenAPI en JSON, con los esquemas `bearerAuth` y `deviceSignature` |
| `http://localhost:8080/actuator/health` | Salud del servicio, sin detalles |

Con `API_DOCS_ENABLED=false`, Swagger UI y `/v3/api-docs` responden `404`. Cada respuesta trae la cabecera `X-Request-Id`, que es el mismo `request_id` de los logs y de los errores.

### Pruebas y calidad

```bash
./mvnw verify             # compila, pruebas unitarias (*Test) y de integración (*IT), Spotless, Checkstyle y SpotBugs
./mvnw spotless:apply     # aplica el formato
```

Las pruebas de integración usan PostgreSQL 18 real con Testcontainers (perfil `test`), por eso necesitan Docker o Podman. El mismo `./mvnw verify` corre en GitHub Actions (`.github/workflows/ci.yml`), junto con CodeQL, *dependency review* y OWASP Dependency-Check (`.github/workflows/security.yml`).

## Repositorios del proyecto

| Repositorio | Contenido |
|---|---|
| `caudal-backend` (este) | API, dominio, seguridad, base de datos y documentación canónica |
| [`caudal-frontend`](https://github.com/NicoalsD/caudal-frontend) | PWA del fontanero, panel de la Junta y página pública |
| [`caudal-ia`](https://github.com/NicoalsD/caudal-ia) | Pronóstico con Chronos |
| [`caudal-simulador`](https://github.com/NicoalsD/caudal-simulador) | Simulador de datos de la región y del hardware |

## Equipo

Nicolas Diaz (`NicoalsD`) · Drako Salazar (`Drako2305`) · Nicolas Mora (`nicomora70`). Proyecto de la materia Patrones de Software.
