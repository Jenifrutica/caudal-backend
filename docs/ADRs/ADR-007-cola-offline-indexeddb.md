# ADR-007: Cola offline en IndexedDB (Dexie) con reenvío idempotente

- **Estado:** Aceptado
- **Fecha:** 2026-11-16 (decisión tomada en la Fase 0 del frontend; aquí se documenta como ADR)
- **Decisores:** equipo CAUDAL
- **Drivers:** D-01, D-07
- **Decisión reemplaza a:** —

## Contexto

- **D-01 (5, 4) Operación sin señal.** RG-01: la vereda no tiene señal estable. RNF-14: lecturas en IndexedDB con UUID del cliente, reenvío idempotente y lotes de hasta 100. HU-09 y HU-10. Escenario: el fontanero registra **sin señal**; al volver la red, la app envía en lotes de **≤ 100**, y un reenvío con el mismo UUID devuelve **la misma respuesta**, con **0** lecturas perdidas o duplicadas.
- **D-07 (4, 2) Pocos toques.** RNF-12: registrar en **≤ 4 toques**, con el estado de conexión siempre visible. La cola no puede pedirle al fontanero que "reintente" a mano.
- Restricciones: el celular puede ser compartido (RG-07), así que la cola es **por persona**. Nada sensible se guarda en el navegador (RNF-11): ni tokens ni contraseñas. El navegador objetivo incluye **Safari en iOS**.

## Decisión

Patrón **Command + Outbox** en el cliente y **idempotencia** en el servidor:

- **Cliente** (`caudal-frontend`):
  - `SubmitReadingCommand` (con `clientId` UUID generado en el celular) se encola en `CommandQueue` (`src/core/commands/`).
  - La persistencia va por el puerto `OutboxRepository`, con el adaptador `IndexedOutboxRepository` sobre `OfflineDatabase` (Dexie, base `caudal-offline`, tablas `outbox`, `referenceCache` y `sessionHints`).
  - `OutboxSync` y `SyncQueueStore` envían cuando hay conexión, por `POST /api/v1/readings/batch` en lotes de hasta 100 (`clientPolicy.ts`).
  - Las reglas y catálogos se guardan en `referenceCache` para validar sin señal.
- **Servidor** (`caudal-backend`): `CreateReadingBatchCommandHandler` usa el UUID como clave. Si el contenido es el mismo, responde igual (`idempotent_replay`); si cambió, responde `409 DUPLICATE_READING`. El lote queda en `ops.sync_batches`.
- El service worker (Workbox, `vite-plugin-pwa`) solo cachea la aplicación. **No** envía datos por su cuenta.

## Alternativas consideradas y descartadas

### Alternativa A: `localStorage`

- **Ventajas:** es la API más simple, síncrona y presente en todos los navegadores.
- **Desventajas:** es síncrona (bloquea la UI), tiene una cuota de unos 5 MB, no tiene transacciones (un cierre a mitad de escritura corrompe la cola) y no tiene índices para filtrar por dueño o estado. Además, la regla del proyecto es "nada sensible en `localStorage`" (RNF-11).
- **Motivo del descarte:** no garantiza las **0 lecturas perdidas** de **D-01**: sin transacciones, un cierre de la app a mitad del guardado deja la cola inconsistente. Así lo registra la tabla de [`Stack-tecnologico.md`](../Stack-tecnologico.md#frontend-caudal-frontend).

### Alternativa B: Background Sync del service worker (Workbox `BackgroundSyncPlugin`)

- **Ventajas:** el navegador reintenta solo, incluso con la pestaña cerrada.
- **Desventajas:** la API **no existe en Safari iOS** ([`offline-sync.md`](https://github.com/Jenifrutica/caudal-frontend/blob/develop/.agents/offline-sync.md) §11). Además reenviaría la petición con el `Authorization` del momento de guardarla, que ya expiró (JWT de 15 min, ADR-005). Tampoco permite mostrar la cola ni corregir una lectura rechazada.
- **Motivo del descarte:** un fontanero con iPhone perdería lecturas, lo que incumple **D-01**. La corrección de una lectura rechazada (HU-11) necesita una cola visible, que pide **D-07**. Se usa solo como señal para que las pestañas abiertas vacíen la cola.

### Alternativa C: IndexedDB directo, sin Dexie

- **Ventajas:** no agrega una dependencia y da control total.
- **Desventajas:** la API es verbosa y basada en eventos, la gestión de versiones de esquema es manual y cuesta más probarla.
- **Motivo del descarte:** más código y más riesgo de errores para el mismo resultado. Dexie aporta tablas tipadas, transacciones y migraciones de esquema, y se prueba con `fake-indexeddb`.

## Consecuencias

- **Positivas:** las lecturas sobreviven a recargas, cierres y fallos de red. Los reenvíos no duplican (la idempotencia vive en el servidor). La cola es visible y corregible, y funciona igual en iOS y Android.
- **Negativas / costo:** hay dos fuentes de verdad temporales (celular y servidor), lógica de conflicto (`409`) en el cliente y migraciones del esquema de IndexedDB (`OFFLINE_SCHEMA_VERSION`).
- **Riesgos y mitigaciones:**
  - *El navegador borra el almacenamiento* → el aviso de "lecturas pendientes" está siempre visible y el respaldo operativo es el cuaderno de papel (RG-01). Pendiente: pedir almacenamiento persistente con `navigator.storage.persist()`, que hoy **no** se llama (dueño: frontend, `NicoalsD`; revisión: cierre del piloto).
  - *Celular compartido* → cada registro guarda su dueño y la cola filtra por persona (prueba "never shows or sends the readings of another person on the same phone").
  - *Sesión vencida con pendientes* → la cola no se borra y se pide volver a entrar (ADR-005).
- **Seguimiento:** se mide el tamaño de la cola en el piloto y se revisa el límite de 100 por lote si cambia el plan gratuito.

## Evidencia

- Código: `caudal-frontend/src/core/commands/{CommandQueue,SubmitReadingCommand,OutboxRepository}.ts`, `caudal-frontend/src/services/offline/{OfflineDatabase,IndexedOutboxRepository}.ts`, `caudal-frontend/src/state/{OutboxSync,SyncQueueStore}.ts`, `src/main/java/co/caudal/application/reading/CreateReadingBatchCommandHandler.java`.
- Pruebas: `caudal-frontend/src/core/commands/CommandQueue.test.ts` ("keeps one record when the same client id is enqueued twice"), `caudal-frontend/src/test/integration/offlineReadings.test.ts`, `caudal-frontend/e2e/operator.spec.ts`; backend `src/test/java/co/caudal/api/controller/ReadingBatchIT.java`.
- Comando de verificación: en `caudal-frontend`, `pnpm vitest run src/core/commands/CommandQueue.test.ts src/test/integration/offlineReadings.test.ts`; en el backend, `./mvnw -B -ntp verify -Dtest=NONE -Dsurefire.failIfNoSpecifiedTests=false -Dit.test=ReadingBatchIT`. Resultados en [`Evidencias-verificacion.md`](../Evidencias-verificacion.md).
