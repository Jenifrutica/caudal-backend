# Decisiones de arquitectura (ADR)

> Registro de las decisiones **de estructura** de CAUDAL. Cada ADR nace de uno o más drivers de [`Drivers.md`](../Drivers.md), compara al menos dos alternativas reales y dice por qué se descartaron. El rastro hasta el código está en [`Trazabilidad-arquitectura.md`](../Trazabilidad-arquitectura.md).

## Formato

Cada ADR tiene cinco secciones obligatorias más la evidencia:

1. **Contexto**: qué fuerza obliga a decidir (drivers con su escenario medible y las restricciones reales).
2. **Decisión**: qué se decidió y dónde está en el código.
3. **Alternativas consideradas y descartadas**: ventajas, desventajas y motivo concreto del descarte.
4. **Consecuencias**: positivas, costos, riesgos con su mitigación y seguimiento.
5. **Evidencia**: archivos, pruebas y el comando que lo demuestra.

Encabezado: estado (`Propuesto`, `Aceptado`, `Reemplazado por ADR-00Y`), fecha, decisores, drivers y a quién reemplaza. Un ADR aceptado no se edita: si la decisión cambia, se escribe uno nuevo que lo reemplaza.

## Índice

| ADR | Decisión | Drivers | Estado |
|---|---|---|---|
| [ADR-001](ADR-001-monolito-modular-hexagonal.md) | Monolito modular con arquitectura hexagonal | D-08, D-06, D-02, D-14 | Aceptado |
| [ADR-002](ADR-002-aislamiento-con-rls.md) | Aislamiento multiacueducto con RLS forzada en PostgreSQL | D-03, D-04, D-10 | Aceptado |
| [ADR-003](ADR-003-pronostico-en-servicio-externo.md) | Pronóstico en un servicio externo con circuito y estimación simple | D-05, D-06, D-13 | Aceptado |
| [ADR-004](ADR-004-postgresql-18.md) | PostgreSQL 18 como única base de datos | D-02, D-03, D-13 | Aceptado |
| [ADR-005](ADR-005-refresh-en-cookie-httponly.md) | Access token en memoria y refresh rotatorio en cookie `HttpOnly` | D-04, D-01 | Aceptado |
| [ADR-006](ADR-006-simulador-como-proceso-separado.md) | Simulador como proceso separado que entra por la API pública | D-15, D-09, D-13, D-06 | Aceptado |
| [ADR-007](ADR-007-cola-offline-indexeddb.md) | Cola offline en IndexedDB (Dexie) con reenvío idempotente | D-01, D-07 | Aceptado |

Los ADR-01 a ADR-06 que estaban en `Arquitectura.md` §12 (formato corto) se migraron a este formato. La elección de Spring Boot 4.1 con Java 25 (antiguo ADR-02) es una decisión de tecnología impuesta por la materia ("backend en Java"), no de estructura. Su justificación y sus alternativas están en [`Stack-tecnologico.md`](../Stack-tecnologico.md#backend-caudal-backend).

## Matriz de alternativas (para la sustentación)

| Decisión | Elegida | Descartada 1 | Descartada 2 | Descartada 3 | Razón principal del descarte |
|---|---|---|---|---|---|
| Estilo del backend | Monolito modular hexagonal | Capas tradicionales | Microservicios por dominio | — | Capas acoplan el dominio a JPA (D-08); microservicios exigen más equipo y más servicios gratuitos de los que hay (D-06) |
| Aislamiento por acueducto | RLS forzada + chequeo por objeto | `WHERE aqueduct_id = ?` en cada consulta | Esquema o BD por acueducto | — | Un olvido en la aplicación expone datos (D-03); un esquema por acueducto multiplica migraciones y rompe D-10 |
| Pronóstico | Servicio externo + circuito + estimación simple | Chronos dentro del backend | Solo estimación simple | — | Embebido rompe 512 MB y el stack Java (D-06); sin IA no hay forma de medir si ayuda (D-13) |
| Base de datos | PostgreSQL 18 | MySQL 8 | MongoDB | — | Sin RLS ni `EXCLUDE` (D-03, D-02); sin restricciones relacionales para turnos y auditoría |
| Sesión del navegador | Access en memoria + refresh en cookie `HttpOnly` | Tokens en `localStorage` | Sesión en el servidor | — | XSS roba el token (D-04); sesión con estado y CSRF clásico en sitios cruzados |
| Datos de prueba | Simulador separado | Semilla dentro del backend | Importar CSV a mano | — | Contamina producción y no ejercita las puertas reales (D-15, D-09) |
| Cola offline | IndexedDB con Dexie | `localStorage` | Solo Background Sync del service worker | — | Sin transacciones y con cuota baja; Background Sync no existe en iOS Safari (D-01) |
