# Trazabilidad de la arquitectura

> Matriz auditable: **driver → escenario → táctica → ADR → componente real → prueba → comando**. Cada ruta y cada clase de esta página se comprobó con `find` y `grep` contra `develop` (`3c87ae3`) el 2026-11-16, y cada comando se ejecutó; sus resultados están en [`Evidencias-verificacion.md`](Evidencias-verificacion.md).
>
> Drivers: [`Drivers.md`](Drivers.md) · Decisiones: [`ADRs/`](ADRs/README.md)

Convención de rutas: sin prefijo = `caudal-backend`; `fe:` = `caudal-frontend`; `ia:` = `caudal-ia`; `sim:` = `caudal-simulador`. `J` = `src/main/java/co/caudal`, `T` = `src/test/java/co/caudal`, `M` = `src/main/resources/db/migration`.

## 1. Matriz

| Driver (I, D) | Escenario medible | Táctica | ADR | Componente real | Prueba / evidencia | Comando |
|---|---|---|---|---|---|---|
| **D-01** Offline-first (5, 4) | Sin señal, 0 lecturas perdidas o duplicadas; lotes ≤ 100; mismo UUID → misma respuesta | Command + Outbox en IndexedDB; reenvío idempotente por UUID del cliente | [007](ADRs/ADR-007-cola-offline-indexeddb.md), [005](ADRs/ADR-005-refresh-en-cookie-httponly.md) | `fe:src/core/commands/CommandQueue.ts`, `fe:src/services/offline/{OfflineDatabase,IndexedOutboxRepository}.ts`, `fe:src/state/OutboxSync.ts`, `J/application/reading/CreateReadingBatchCommandHandler.java` | `fe:src/core/commands/CommandQueue.test.ts`, `fe:src/test/integration/offlineReadings.test.ts`, `T/api/controller/ReadingBatchIT.java`, `fe:e2e/operator.spec.ts` | `pnpm vitest run src/core/commands/CommandQueue.test.ts src/test/integration/offlineReadings.test.ts` |
| **D-02** Decisión trazable (5, 3) | Cada decisión deja una fila de auditoría; `UPDATE` o `DELETE` *append-only* → la BD lo rechaza | Tablas *append-only* con triggers; auditoría con cadena de hashes; instantáneas; una transacción por caso de uso | [004](ADRs/ADR-004-postgresql-18.md), [001](ADRs/ADR-001-monolito-modular-hexagonal.md) | `M/V27__ops_proposal_snapshots_and_decisions.sql`, `M/V35__audit_log.sql`, `M/V39__append_only_and_updated_at_triggers.sql`, `M/V42__audit_hash_chain.sql`, `J/infrastructure/persistence/AuditLogPersistenceAdapter.java`, `J/application/port/out/UnitOfWorkPort.java` | `T/infrastructure/persistence/AppendOnlyAndTriggersIT.java`, `T/api/controller/AuditTrailIT.java`; en local, `UPDATE ops.readings` como `caudal_app` → `permission denied` | `./mvnw verify -Dtest=NONE -Dsurefire.failIfNoSpecifiedTests=false -Dit.test='AppendOnlyAndTriggersIT,AuditTrailIT'` |
| **D-03** Aislamiento (5, 4) | Recurso de otro acueducto → 404; sin `app.aqueduct_id` → 0 filas | RLS forzada en 37 tablas + `set_config` por transacción + chequeo por objeto | [002](ADRs/ADR-002-aislamiento-con-rls.md) | `M/V1__schemas_extensions_and_roles.sql`, `M/V43__row_level_security.sql`, `J/infrastructure/persistence/AqueductSessionContext.java` | `T/api/controller/AqueductIsolationIT.java`, `T/infrastructure/security/EndpointAuthorizationIT.java`; en local, `SELECT count(*) FROM org.tanks` como `caudal_app` → 0 | `./mvnw verify -Dtest=NONE -Dsurefire.failIfNoSpecifiedTests=false -Dit.test=AqueductIsolationIT` |
| **D-04** Cuentas (5, 3) | JWT de 15 min; reuso de refresh → revoca la familia; 5 fallos → bloqueo; Argon2id | Token corto en memoria + refresh rotatorio en cookie `HttpOnly` + bloqueo por intentos + roles sin privilegios | [005](ADRs/ADR-005-refresh-en-cookie-httponly.md), [002](ADRs/ADR-002-aislamiento-con-rls.md) | `J/application/auth/RefreshTokenService.java`, `J/api/security/{RefreshCookieFactory,RefreshRequestGuard}.java`, `J/infrastructure/security/{Argon2PasswordHasherAdapter,TokenVersionValidator}.java`, `J/domain/user/LockoutPolicy.java` | `T/application/auth/RefreshTokenServiceTest.java`, `T/api/security/RefreshCookieTest.java`, `T/domain/session/RefreshTokenStateTest.java`, `T/domain/user/LockoutPolicyTest.java` | `./mvnw -q -Dtest='RefreshTokenServiceTest,RefreshCookieTest,RefreshTokenStateTest' test` |
| **D-05** La IA no bloquea (5, 3) | IA caída → estimación simple; 2 s / 10 s; 5 fallos → circuito abierto 60 s | Proxy + circuit breaker (State) + respaldo | [003](ADRs/ADR-003-pronostico-en-servicio-externo.md) | `J/infrastructure/forecast/{RemoteForecasterProxy,CircuitBreakerState,IaForecastClientAdapter}.java`, `J/application/forecast/BaselineForecaster.java`, `J/domain/forecast/NaivePersistenceStrategy.java` | `T/infrastructure/forecast/RemoteForecasterProxyTest.java`, `T/infrastructure/forecast/CircuitBreakerStateTest.java`, `T/domain/forecast/NaivePersistenceStrategyTest.java` | `./mvnw -q -Dtest='RemoteForecasterProxyTest,CircuitBreakerStateTest' test` |
| **D-06** Costo ≈ 0 (4, 2) | $0/mes en planes gratuitos; la IA cabe en 512 MB; un solo servicio Java | Monolito de un proceso; imágenes multietapa con *digest* fijado; modelo pequeño horneado en la imagen | [001](ADRs/ADR-001-monolito-modular-hexagonal.md), [003](ADRs/ADR-003-pronostico-en-servicio-externo.md), [006](ADRs/ADR-006-simulador-como-proceso-separado.md) | `render.yaml`, `Dockerfile` (`eclipse-temurin:25` con `sha256`), `ia:render.yaml` (`plan: free`), `ia:Dockerfile` (`chronos-bolt-tiny`, `HF_HUB_OFFLINE=1`) | Producción: `/actuator/health` UP y `/v3/api-docs` 200 en Render; IA `/v1/health` 200 | `make up && make smoke` (local); `curl https://caudal-api-7crk.onrender.com/actuator/health` |
| **D-07** ≤ 4 toques (4, 2) | Lectura válida en ≤ 4 toques, objetivos de 48 px y conexión siempre visible | Formulario de un paso con el esquema de reglas en caché; cola automática | [007](ADRs/ADR-007-cola-offline-indexeddb.md) | `fe:src/features/readings/{ReadingPage,ReadingForm}.tsx`, `fe:src/features/readings/readingQueries.ts` | `fe:e2e/operator.spec.ts` ("registra una lectura sin señal, la ve en pendientes y se envía al volver la red"), `fe:src/features/readings/ReadingPage.test.tsx` | `pnpm vitest run src/features/readings` |
| **D-08** Pruebas sin BD (4, 4) | Dominio sin Spring/BD; 11 reglas ArchUnit en verde; dominio ≥ 90 % | Hexágono (puertos/adaptadores) + ArchUnit en CI + JaCoCo | [001](ADRs/ADR-001-monolito-modular-hexagonal.md) | `J/{api,application,domain,infrastructure,shared}`, 56 puertos en `J/application/port/out/`, `.github/workflows/ci.yml` (`./mvnw -B -ntp verify`) | `T/architecture/ArchitectureTest.java`; pruebas de dominio en `T/domain/` | `./mvnw -q -Dtest=ArchitectureTest test` |
| **D-09** Hardware real (2, 4) | El sensor futuro usa la misma API: Ed25519, ±300 s, nonce de 10 min | Telemetría firmada y comandos de válvula solo desde turnos; el simulador como hardware virtual | [006](ADRs/ADR-006-simulador-como-proceso-separado.md) | `J/infrastructure/device/DeviceTelemetryAdapter.java`, `sim:src/caudal_sim/{signing,devices,valve_actuator}.py` | `T/infrastructure/device/DeviceTelemetryAdapterTest.java`, `sim:tests/test_signing.py` | `uv run pytest -q tests/test_signing.py` (sim) |
| **D-10** Acueducto nuevo (3, 3) | Alta solo con datos: 0 migraciones, 0 código, 0 esquemas | Multiacueducto por fila (`aqueduct_id`) + RLS; membresías por API | [002](ADRs/ADR-002-aislamiento-con-rls.md) | `M/V47__seed_demo_aqueduct.sql` (el demo nace igual: una fila), `J/api/controller/MembershipController.java`, `J/infrastructure/persistence/MembershipPersistenceAdapter.java` | `T/api/controller/AqueductIsolationIT.java` (crea dos acueductos solo con datos y prueba que no se ven entre sí) | Ídem D-03 |
| **D-11** Accesibilidad (3, 2) | Contraste ≥ 4,5:1; 0 violaciones de axe | Componentes de UI accesibles; axe en Playwright | — (táctica, ver `Drivers.md` §6) | `fe:.agents/ux-guidelines.md`, `fe:src/ui/` | `fe:e2e/accessibility.spec.ts` (portada, horario público, fontanero, Junta) | `pnpm exec playwright test e2e/accessibility.spec.ts` (requiere navegadores de Playwright) |
| **D-12** Facturación (1, 5) | No se ofrece | Exclusión de alcance | — (evitar) | `docs/Caudal.md` §3.2 | No aplica | No aplica |
| **D-13** Calidad del pronóstico (4, 3) | ≥ 30 evaluaciones; MAE, WQL, cobertura 70–90 %, *skill* | Pronóstico en sombra + backtest con series reproducibles | [003](ADRs/ADR-003-pronostico-en-servicio-externo.md), [006](ADRs/ADR-006-simulador-como-proceso-separado.md), [004](ADRs/ADR-004-postgresql-18.md) | `J/application/forecast/ShadowBaselineForecaster.java`, `ia:src/caudal_ia/evaluation/{backtest,metrics,report}.py`, `sim:scenarios/normal-year.yaml` | `T/application/forecast/ShadowBaselineForecasterTest.java`, `ia:tests/evaluation/test_backtest.py`, `sim:tests/test_reproducibility.py`; resultado medido en `Modulo-IA.md` §9 (`does_not_help` con datos simulados) | `uv run pytest -q` (ia y sim) |
| **D-14** Página pública (3, 2) | ≤ 1 s; 0 datos personales | Proxy de protección que quita autor y estado interno | — (táctica dentro de [001](ADRs/ADR-001-monolito-modular-hexagonal.md)) | `J/infrastructure/publication/PublicScheduleProxy.java`, `J/api/controller/PublicScheduleController.java`, `fe:src/features/public/PublicScheduleContent.tsx` | `T/infrastructure/publication/PublicScheduleProxyTest.java` (`aPublishedScheduleLosesWhoPublishedItAndItsInternalStatus`) | `./mvnw -q -Dtest=PublicScheduleProxyTest test` |
| **D-15** Simulado ≠ real (4, 2) | "Datos simulados" en todo lo demo; importar en un acueducto real → error | Bandera `is_demo` + doble guardia (API y simulador) | [006](ADRs/ADR-006-simulador-como-proceso-separado.md) | `J/application/simulation/ImportHistoryCommand.java`, `sim:src/caudal_sim/demo_guard.py`, `fe:src/features/public/PublicScheduleContent.tsx` (`SimulatedDataBanner`) | `T/api/controller/ImportIT.java` (`aRealAqueductIsDemoOnlyAndAnOperatorCannotImport`), `sim:tests/test_demo_guard.py`, `sim:tests/test_import_safety.py` | `./mvnw verify -Dtest=NONE -Dsurefire.failIfNoSpecifiedTests=false -Dit.test=ImportIT` |

Cobertura: 15 de 15 drivers con fila; los 10 de importancia 4–5 tienen ADR y prueba; los 4 cuadrantes están representados (estratégico: D-01, D-03, D-08; quick win: D-02, D-04 a D-07, D-13, D-15; incremental: D-10, D-11, D-14; diferir/evitar: D-09, D-12).

## 2. Decisiones sin driver

Ninguna. Los 7 ADR citan al menos un driver (ver la columna "Drivers" del [índice](ADRs/README.md)). La elección de Spring Boot 4.1 con Java 25 (antiguo ADR-02 de `Arquitectura.md`) no es una decisión de estructura sino una restricción de la materia ("backend en Java", `AGENTS.md` §1), y su justificación vive en [`Stack-tecnologico.md`](Stack-tecnologico.md).

## 3. Drivers sin decisión

| Driver | Justificación |
|---|---|
| D-11 Accesibilidad | Importancia 3; táctica de UI sin alternativas estructurales (ver [`Drivers.md`](Drivers.md) §6). |
| D-12 Facturación | Importancia 1; fuera del problema (`Caudal.md` §3.2). Se evita a propósito. |
| D-14 Página pública | Importancia 3; se atiende con el proxy `PublicScheduleProxy` dentro del hexágono (ADR-001). |

Ningún driver de importancia 4–5 queda sin ADR.

## 4. Deriva detectada (documentación ↔ código)

Revisión de [`Arquitectura.md`](Arquitectura.md) contra el código el 2026-11-16. Todas las filas quedaron **cerradas** en esta misma rama: se corrigió la documentación, porque el código es el que está probado y desplegado.

| Documentado | Código real | Acción |
|---|---|---|
| `application/uow/UnitOfWork` y `SpringUnitOfWork` | `application/port/out/UnitOfWorkPort.java` y `infrastructure/persistence/SpringUnitOfWorkAdapter.java` | Corregido en §2.4 y §6 |
| Persistencia con `*JpaRepository` y `*Entity` (`ReadingJpaRepository`, `ReadingEntity`) | 42 archivos de `src/main` usan `JdbcClient`; JPA solo en `UserEntity`, `UserJpaRepository`, `RefreshTokenEntity` y `RefreshTokenJpaRepository` | Corregido en §2.1, §2.4 y §6 |
| `NaivePersistenceForecastAdapter` | `BaselineForecaster`, `NaivePersistenceStrategy` y `ShadowBaselineForecaster` | Corregido en §2.4 y §4 |
| `PublicPageChannel`, `PosterChannel` en `infrastructure/publication` | `application/publication/{PublicationChannel,PlainTextChannel,WhatsAppChannel}`; documentos en `infrastructure/document/{DocumentFactory,PdfDocumentFactory,PosterGenerator,MinutesGenerator}` | Corregido en §2.4 |
| Handlers `RangeCheckHandler`, `DateCheckHandler`, `DuplicateCheckHandler`, `JumpCheckHandler`, `AgeCheckHandler` | `GaugeRangeHandler`, `TimestampHandler`, `TimestampWindowHandler`, `DuplicateHandler`, `SuddenJumpHandler`, `AgeHandler` | Corregido en §3 |
| `RecordReadingUseCase.execute` y `RecordReadingInput` | `CreateReadingCommand` con `ReadingInput`, atendido por `CreateReadingCommandHandler` y `CreateReadingBatchCommandHandler` (vía `CommandBus`) | Corregido en §3 |
| `TankStatusController` | `TankController` (delega en `TankStatusFacade`) | Corregido en §4 |
| Eventos publicados "después del commit" con `@TransactionalEventListener(AFTER_COMMIT)` | `SimpleDomainEventPublisher` entrega en la misma transacción a `RuleSetActivationAuditor` y `SchedulePublicationAuditor`; no hay `@TransactionalEventListener` en `src/main` | Corregido en §5 y §6: la auditoría se revierte con la decisión (D-02) |
| `READ COMMITTED (… verificar)` | Ningún `Isolation.` en `src/main`: se usa el predeterminado de PostgreSQL | Corregido en §6 |
| "Turnos que cruzan la medianoche se verifican en pruebas" | No hay prueba dedicada | §8 abierto con dueño (`Drako2305`) y revisión al cerrar la siguiente fase |
| Evento `ReadingAccepted`; `SpringDomainEventPublisher` en `infrastructure.event` | Eventos `RuleSetActivated`, `SchedulePublished`, `ValveCommandConfirmed` y `ValveCommandDelivered`; `SimpleDomainEventPublisher` en `application.event` | Corregido en §2.4 y §5 |
| Paquetes `application/usecase`, `domain/catalog`, `domain/exception`, `infrastructure/event` | No existen. Existen `application/{reading,rules,schedule,…}` por módulo, `domain/{anomaly,device,evaluation,execution,incident,mfa,security,session,user,…}` e `infrastructure/{logging,ratelimit}` | Árbol §2.4 regenerado desde `find` |
| "Árbol de carpetas propuesto… se confirma en la Fase 1 (verificar)" | La estructura está implementada | §2.4 marcada como implementada y verificada |
| CI: "los demás workflows son propuestos (verificar)" | Existen `ci.yml`, `commit-lint.yml`, `security.yml` (CodeQL, *dependency review*, OWASP) y `render-deploy.yml` | Tabla §11 corregida |
| §12 con 6 ADR de tres secciones | 7 ADR de cinco secciones en `docs/ADRs/` | §12 convertida en índice |

## 5. Cómo revisar en 5 minutos

Con los cuatro repositorios clonados como carpetas hermanas:

```bash
cd caudal-backend

# 1. Drivers: 15 filas, 4 cuadrantes, 20 % estratégico
grep -cE '^\| D-[0-9]{2} \|.*\| [1-5] \| [1-5] \|' docs/Drivers.md        # 15
grep -E '^\| D-[0-9]{2} \|.*\| [1-5] \| [1-5] \|' docs/Drivers.md | awk -F'|' '{print $8}' | sort | uniq -c
#   3 Estratégico · 7 Quick win · 3 Incremental · 1 Diferir · 1 Evitar

# 2. ADR: cinco secciones en cada uno
for f in docs/ADRs/ADR-*.md; do
  printf '%s ' "$f"; grep -cE '^## (Contexto|Decisión|Alternativas consideradas y descartadas|Consecuencias|Evidencia)$' "$f"
done                                                                   # 5 en cada uno

# 3. Cada driver aparece en la trazabilidad y cada ADR cita drivers
for d in $(seq -w 1 15); do grep -q "D-$d" docs/Trazabilidad-arquitectura.md || echo "falta D-$d"; done
grep -L 'Drivers:\*\* D-' docs/ADRs/ADR-*.md                          # vacío

# 4. Estructura del código = estructura documentada
JAVA_HOME=/ruta/a/jdk-25 ./mvnw -q -Dtest=ArchitectureTest test

# 5. El sistema completo corre con un comando
make up && make smoke                                                  # 9 OK
```
