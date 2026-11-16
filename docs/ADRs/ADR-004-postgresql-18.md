# ADR-004: PostgreSQL 18 como única base de datos

- **Estado:** Aceptado
- **Fecha:** 2026-11-16 (amplía el ADR-03 de `Arquitectura.md`, que trataba solo la RLS)
- **Decisores:** equipo CAUDAL
- **Drivers:** D-02, D-03, D-13
- **Decisión reemplaza a:** — (decisión implícita en `Stack-tecnologico.md`; aquí se documenta con sus alternativas)

## Contexto

- **D-02 (5, 3) Decisión trazable.** RNF-19: las tablas *append-only* solo admiten `INSERT` y `SELECT` para `caudal_app`; la auditoría lleva una cadena de hashes anclada; las correcciones nunca borran el dato original. Escenario: cualquier intento de `UPDATE` o `DELETE` sobre una tabla *append-only* con `caudal_app` **lo rechaza la BD**, no solo el código.
- **D-03 (5, 4) Aislamiento.** Requiere RLS forzada (ADR-002).
- **D-13 (4, 3) Calidad medible.** Hay que guardar dos pronósticos por instante (IA y en sombra), con cuantiles y su procedencia, y consultarlos por ventanas de tiempo.
- El modelo es **relacional por naturaleza**: reglas versionadas, bandas de nivel y turnos que **no pueden solaparse**, sectores con orden, y propuestas con estados y bloqueo optimista (RNF-26). Son 57 tablas en 7 esquemas.
- Restricción de costo (D-06): tiene que existir un plan gratuito administrado con PITR (Neon).

## Decisión

**PostgreSQL 18** es la única base de datos y la fuente de verdad. Se usan sus capacidades como **parte del diseño**, no solo como almacenamiento:

- `FORCE ROW LEVEL SECURITY` por acueducto (`V43__row_level_security.sql`), ver ADR-002.
- Triggers de inmutabilidad y *append-only* (`V39__append_only_and_updated_at_triggers.sql`, `V40__rule_set_immutability.sql`), auditoría con cadena de hashes y anclas (`V35__audit_log.sql`, `V36__audit_anchors.sql`, `V42__audit_hash_chain.sql`).
- Restricciones `EXCLUDE` con `btree_gist` para que bandas y turnos no se solapen (`V18__org_rule_children.sql`, `V26__ops_schedule_items.sql`).
- Instantáneas de la propuesta y decisiones de la Junta (`V27__ops_proposal_snapshots_and_decisions.sql`).
- `uuidv7()` nativo para identificadores y `timestamptz` en UTC.
- Migraciones con Flyway; local con Docker Compose (`postgres:18`) y producción en Neon.

## Alternativas consideradas y descartadas

### Alternativa A: MySQL 8

- **Ventajas:** muy difundido, con buen soporte en hosting gratuito y conocido por el equipo de otras materias.
- **Desventajas:** no tiene RLS nativa equivalente (habría que simularla con vistas por usuario o filtros en la aplicación). Tampoco tiene restricciones `EXCLUDE` para impedir solapes de rangos, que habría que validar en código con condiciones de carrera.
- **Motivo del descarte:** sin RLS se cae la primera capa de **D-03** (ADR-002), y sin `EXCLUDE` la regla "dos turnos no se solapan" queda solo en la aplicación, vulnerable a dos decisiones simultáneas de la Junta. Así lo registra la tabla de [`Stack-tecnologico.md`](../Stack-tecnologico.md#base-de-datos).

### Alternativa B: MongoDB (documentos)

- **Ventajas:** esquema flexible. Guardar series del tanque o actas como documentos es natural y Atlas tiene plan gratuito.
- **Desventajas:** el dominio está lleno de relaciones con integridad (regla vigente → bandas → turnos → comandos de válvula → auditoría). Las transacciones multidocumento existen, pero son más costosas. No hay RLS ni triggers de inmutabilidad, y la cadena de hashes de auditoría pierde las garantías de orden.
- **Motivo del descarte:** rompe **D-02**: la inmutabilidad y la auditoría pasarían a depender del código, no de la base. La flexibilidad de esquema no aporta nada a un dominio cuyas reglas son fijas y versionadas.

### Alternativa C: PostgreSQL + una base de series de tiempo aparte (TimescaleDB o InfluxDB) para lecturas y pronósticos

- **Ventajas:** consultas de ventanas y agregaciones muy rápidas.
- **Desventajas:** suma una segunda base que operar, respaldar y aislar por acueducto. El volumen de CAUDAL es de pocas lecturas por día por tanque.
- **Motivo del descarte:** **D-06**: no hay plan gratuito que justifique otra pieza para un volumen tan pequeño, y la RLS habría que duplicarla.

## Consecuencias

- **Positivas:** las garantías de D-02 y D-03 viven en la base y sobreviven a errores del código. Las reglas de solape no tienen condiciones de carrera. Un solo motor que respaldar (PITR de Neon).
- **Negativas / costo:** la lógica queda repartida entre Java y SQL (triggers y políticas). Las pruebas exigen PostgreSQL real con Testcontainers y Docker, y la portabilidad a otro motor es baja.
- **Riesgos y mitigaciones:**
  - *Cuotas de Neon free* (RG-11) → índices adecuados, lotes de hasta 100 lecturas y exportación documentada.
  - *Triggers que nadie recuerda* → `AppendOnlyAndTriggersIT` comprueba que cada tabla *append-only* tenga sus triggers.
- **Seguimiento:** cada migración nueva se revisa contra `Seguridad-de-la-base-de-datos.md` (RLS, triggers, privilegios por columna).

## Evidencia

- Código: `src/main/resources/db/migration/` (53 migraciones; V18, V26, V27, V35, V36, V39, V40, V42 y V43 citadas arriba), `docker-compose.yml` (servicio `db`).
- Pruebas: `src/test/java/co/caudal/infrastructure/persistence/AppendOnlyAndTriggersIT.java` (por ejemplo `readingsCannotBeUpdatedEvenByTheOwner`), `src/test/java/co/caudal/api/controller/AuditTrailIT.java`, `AuditLogIT.java`.
- Comando de verificación: `./mvnw -B -ntp verify -Dtest=NONE -Dsurefire.failIfNoSpecifiedTests=false -Dit.test=AppendOnlyAndTriggersIT`. Resultado en [`Evidencias-verificacion.md`](../Evidencias-verificacion.md).
