# ADR-002: Aislamiento multiacueducto con RLS forzada en PostgreSQL

- **Estado:** Aceptado
- **Fecha:** 2026-11-16 (migra el ADR-03 de `Arquitectura.md`)
- **Decisores:** equipo CAUDAL
- **Drivers:** D-03, D-04, D-10
- **Decisión reemplaza a:** ADR-03 de `Arquitectura.md` §12 (formato corto)

## Contexto

- **D-03 (5, 4) Aislamiento entre acueductos.** CAUDAL es multiacueducto desde el diseño: el acueducto demo convive con los reales en la misma base (RF-40, RNF-07). Escenario: un usuario del acueducto A pide un recurso de B, **aunque el código olvide el filtro**; la API responde **404** y la tabla devuelve **0 filas**.
- **D-04 (5, 3) Mínimo privilegio.** RNF-07 pide autorización que niega por defecto, por permiso y por acueducto, y RNF-26 pide roles separados (`caudal_migrator`, `caudal_app`, `caudal_readonly`).
- **D-10 (3, 3) Acueducto nuevo sin código.** Una vereda nueva se da de alta **solo con datos**: 0 migraciones, 0 esquemas nuevos.
- Restricciones: Neon en el plan gratuito (una base, sin superusuario para la aplicación); 57 tablas en 7 esquemas; equipo de 3 personas que escribe SQL a mano con `JdbcClient`.

## Decisión

Defensa en **dos capas**:

1. **En la base de datos:** `FORCE ROW LEVEL SECURITY` en las tablas con datos de un acueducto. La migración `V43__row_level_security.sql` lo aplica a **37 tablas**. Las políticas comparan `aqueduct_id` con `audit.current_aqueduct_id()`, que lee `current_setting('app.aqueduct_id')`. Sin ese valor, **ninguna fila es visible**: la comparación con `NULL` falla cerrada.
2. **En la aplicación:** `AqueductSessionContext` fija `set_config('app.aqueduct_id', …, true)` (equivalente a `SET LOCAL`) dentro de cada transacción, con el acueducto tomado **solo del JWT validado**. El caso de uso además verifica el objeto (por ejemplo, que el tanque pertenezca al acueducto de la membresía) y responde 404 si no.

`caudal_app` se crea en `V1__schemas_extensions_and_roles.sql` **sin** `SUPERUSER` ni `BYPASSRLS`; la migración falla si alguien le dio esos atributos.

## Alternativas consideradas y descartadas

### Alternativa A: filtro en la aplicación (`WHERE aqueduct_id = ?` en cada consulta)

- **Ventajas:** simple de entender y portable a cualquier base. No necesita variables de sesión y es fácil de depurar.
- **Desventajas:** depende de que **cada** consulta de cada desarrollador recuerde el filtro. Con 56 puertos y decenas de consultas SQL escritas a mano, un solo olvido expone datos de otra vereda. No protege accesos fuera de la API (una consulta de reportes o un script).
- **Motivo del descarte:** incumple el escenario de **D-03** ("aunque el código olvide el filtro"). El costo de un olvido (datos personales de otra Junta, RG-10) es mucho mayor que el de mantener políticas RLS. Se conserva como **segunda** capa, no como la única.

### Alternativa B: un esquema o una base de datos por acueducto

- **Ventajas:** aislamiento físico fuerte. Se puede respaldar y borrar un acueducto por separado.
- **Desventajas:** cada migración Flyway se aplica N veces y el *pool* de conexiones se multiplica. Los reportes entre acueductos (evaluación de la IA del equipo, HU-33) se vuelven consultas federadas. En Neon free hay un solo proyecto con límite de almacenamiento y de cómputo (RG-11).
- **Motivo del descarte:** rompe **D-10**: dar de alta una vereda exigiría crear un esquema y migrarlo, es decir, operación y no datos. Además multiplica el costo de **D-06** y el riesgo de deriva entre esquemas.

### Alternativa C: filtro automático del ORM (Hibernate `@Filter` / `@TenantId`)

- **Ventajas:** el filtro se aplica de forma transparente a las entidades JPA.
- **Desventajas:** solo cubre las consultas que pasan por Hibernate. CAUDAL usa `JdbcClient` en la mayoría de los adaptadores (42 archivos de `src/main`) y JPA solo en usuarios y refresh tokens, así que el filtro no vería casi nada.
- **Motivo del descarte:** cobertura parcial, con la misma debilidad que la alternativa A para todo el SQL directo.

## Consecuencias

- **Positivas:** un olvido en el código no filtra datos (la BD falla cerrada). Un acueducto nuevo es una fila en `org.aqueducts` más sus membresías (D-10). Las vistas de reportes heredan el aislamiento.
- **Negativas / costo:** cada transacción hace un `set_config` adicional; las políticas complican el `EXPLAIN` y la depuración. Las pruebas de integración necesitan PostgreSQL real (Testcontainers), no H2.
- **Riesgos y mitigaciones:**
  - *La conexión del pool conserva el acueducto anterior* → `set_config(…, true)` es local a la transacción y PostgreSQL lo descarta al terminar.
  - *Conectarse como superusuario anula la RLS* → en producción la API usa `caudal_app`. En el arranque local, `docker/db-init/10-app-role.sh` crea `caudal_app` con contraseña para que la RLS también se aplique en desarrollo (ver [`Arranque-local.md`](../Arranque-local.md)).
  - *Una tabla nueva sin política* → la regla de revisión está en [`Seguridad-de-la-base-de-datos.md`](../Seguridad-de-la-base-de-datos.md) y la prueba de aislamiento falla si una tabla filtra.
- **Seguimiento:** cada migración que crea una tabla con `aqueduct_id` debe agregarla a la RLS. Se revisa al cerrar cada fase.

## Evidencia

- Código: `src/main/resources/db/migration/V1__schemas_extensions_and_roles.sql`, `V43__row_level_security.sql`, `src/main/java/co/caudal/infrastructure/persistence/AqueductSessionContext.java`.
- Pruebas: `src/test/java/co/caudal/api/controller/AqueductIsolationIT.java` (un acueducto no ve ni opera los recursos de otro), `src/test/java/co/caudal/infrastructure/security/EndpointAuthorizationIT.java`.
- Comando de verificación: `./mvnw -B -ntp verify -Dtest=NONE -Dsurefire.failIfNoSpecifiedTests=false -Dit.test=AqueductIsolationIT` (requiere Docker para Testcontainers). Resultado en [`Evidencias-verificacion.md`](../Evidencias-verificacion.md).
