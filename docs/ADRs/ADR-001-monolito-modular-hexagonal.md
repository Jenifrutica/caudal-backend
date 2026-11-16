# ADR-001: Monolito modular con arquitectura hexagonal

- **Estado:** Aceptado
- **Fecha:** 2026-11-16 (migra el ADR-01 de `Arquitectura.md`, decidido en la Fase 0)
- **Decisores:** equipo CAUDAL
- **Drivers:** D-08, D-06, D-02, D-14
- **Decisión reemplaza a:** ADR-01 de `Arquitectura.md` §12 (formato corto)

## Contexto

- **D-08 (4, 4) Mantenibilidad y pruebas sin BD.** Las reglas de negocio (cadena de validación de lecturas, asignación de turnos, estados de la propuesta, cierre del día) son el corazón de la materia *Patrones de Software*. RNF-17 exige que el dominio no dependa de Spring, JPA ni Jackson. RNF-18 pide cada patrón con interfaz, clase y prueba propias. Escenario: un cambio de regla se prueba **sin Spring ni BD**, las **11** reglas de `ArchitectureTest` siguen en verde y el dominio queda con cobertura **≥ 90 %**.
- **D-06 (4, 2) Costo ≈ 0 y equipo de 3.** Un servicio web de Render free y una base de Neon. Tres integrantes, uno de ellos incorporado tarde (RG-05, RG-13).
- **D-02 (5, 3) Decisión trazable.** Una decisión de la Junta toca propuesta, turnos, publicación, comandos de válvula y auditoría **en la misma transacción**.
- **D-14 (3, 2) Página pública sin datos personales.** La salida pública debe pasar por un filtro único.
- Hay **muchos adaptadores**: PostgreSQL, el servicio de IA, la generación de PDF, los dispositivos firmados y el reloj. Cada uno debe poder cambiarse o simularse en pruebas.

## Decisión

Un **único proceso Spring Boot** (`caudal-backend`) organizado en **puertos y adaptadores**, con las dependencias apuntando hacia el dominio, y verificado por ArchUnit en cada build:

```text
co.caudal.api  ──►  co.caudal.application  ──►  co.caudal.domain  ◄──  co.caudal.infrastructure
                         (puertos *Port)          (Java puro)          (*Adapter, *Proxy)
co.caudal.shared: FieldLimits, SystemClock, ErrorCode (sin dependencias hacia las demás)
```

- **Puertos de salida:** 56 interfaces `*Port` en `co.caudal.application.port.out` (por ejemplo `ReadingPort`, `ForecasterPort`, `UnitOfWorkPort`, `PublicSchedulePort`).
- **Adaptadores:** `infrastructure.persistence` (`ReadingPersistenceAdapter` con `JdbcClient`, `SpringUnitOfWorkAdapter`), `infrastructure.forecast` (`IaForecastClientAdapter`, `RemoteForecasterProxy`), `infrastructure.publication` (`PublicScheduleProxy`), `infrastructure.document` (`PdfDocumentFactory`), `infrastructure.device` (`DeviceTelemetryAdapter`).
- **Transacción por caso de uso** con `UnitOfWorkPort`: una decisión de la Junta escribe todo o nada (D-02).
- **Reglas verificadas:** `ArchitectureTest` (ARCH-01 a ARCH-11) falla el build si el dominio importa Spring, JPA o Jackson, si hay ciclos, o si un adaptador queda fuera de `infrastructure`.
- **Monolito modular**, no distribuido: los módulos de negocio (`reading`, `rules`, `schedule`, `publication`, `minutes`, `device`, etc.) son paquetes dentro de cada capa, no servicios separados. Los únicos procesos aparte son la IA (ADR-003) y el simulador (ADR-006), por razones propias.

## Alternativas consideradas y descartadas

### Alternativa A: arquitectura en capas tradicional (controller → service → repository JPA)

- **Ventajas:** es la forma por defecto de Spring y la que el equipo conocía. Tiene menos clases (no hay puertos ni mapeadores) y sale más rápido al principio.
- **Desventajas:** el servicio depende de los repositorios de Spring Data y de entidades `@Entity`, así que el dominio queda atado a JPA. Probar una regla de asignación de turnos exige levantar el contexto o simular repositorios de Spring. No hay un punto natural para cambiar la IA por la estimación simple ni para filtrar la salida pública.
- **Motivo del descarte:** rompe **D-08**. RNF-17 pide un dominio sin Spring/JPA, y con capas eso no se puede comprobar con ArchUnit sin excepciones. Además, la materia evalúa patrones explícitos (RNF-18), que en capas quedan escondidos detrás de anotaciones.

### Alternativa B: microservicios por dominio (lecturas, turnos, publicación, auth)

- **Ventajas:** cada servicio se despliega y escala por separado. Aísla fallas y los límites de cada contexto quedan explícitos.
- **Desventajas:** cada servicio necesita su propio despliegue, base o esquema, observabilidad y contrato. Una decisión de la Junta (D-02) cruzaría 3 o 4 servicios: haría falta una saga o un *outbox* distribuido para que la auditoría y los comandos de válvula queden consistentes.
- **Motivo del descarte:** rompe **D-06**. Render free da un servicio web gratuito que se duerme (RG-04), y con 4 servicios Java habría 4 arranques en frío encadenados y 4 imágenes de **≥ 512 MB**. Con un equipo de **3 personas** (RG-13), el costo de operación superaría al de construir. La consistencia de D-02 se resuelve gratis con **una** transacción local.

### Alternativa C: monolito sin capas internas ("todo en el controlador")

- **Ventajas:** mínimo de archivos y entrega muy rápida de un CRUD.
- **Desventajas:** mezcla HTTP, SQL y reglas, y no se puede probar sin la base.
- **Motivo del descarte:** incumple **D-08** y RNF-18 desde el primer día. Ni siquiera llega a la sustentación.

## Consecuencias

- **Positivas:** las pruebas del dominio corren en milisegundos y sin Docker. La IA, el PDF y los dispositivos se cambian por dobles de prueba. Una sola transacción garantiza la trazabilidad de D-02. Se despliega **un** contenedor (D-06).
- **Negativas / costo:** más clases (puertos, adaptadores, mapeadores DTO ↔ `*Input`), 56 puertos de salida, y una curva de aprendizaje para el integrante que llega tarde.
- **Riesgos y mitigaciones:** el riesgo es que el hexágono se erosione con el tiempo; lo mitiga `ArchitectureTest` en CI (`ci.yml`). El otro es que el monolito crezca demasiado; los paquetes por módulo permiten extraer uno más adelante sin tocar el dominio.
- **Seguimiento:** se revisa si un módulo necesita escalar por separado (hoy ninguno) o si el equipo crece a más de 6 personas.

## Evidencia

- Código: `src/main/java/co/caudal/{api,application,domain,infrastructure,shared}`, `application/port/out/*Port.java`, `infrastructure/persistence/SpringUnitOfWorkAdapter.java`.
- Pruebas: `src/test/java/co/caudal/architecture/ArchitectureTest.java` (11 reglas `@ArchTest`); pruebas de dominio sin Spring en `src/test/java/co/caudal/domain/`.
- Comando de verificación: `./mvnw -q -Dtest=ArchitectureTest -Dsurefire.failIfNoSpecifiedTests=false test` (resultado en [`Evidencias-verificacion.md`](../Evidencias-verificacion.md)).
- Arranque que demuestra un solo proceso de API más los servicios de apoyo: `make up` (ver [`Arranque-local.md`](../Arranque-local.md)).
