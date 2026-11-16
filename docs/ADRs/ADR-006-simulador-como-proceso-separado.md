# ADR-006: Simulador como proceso separado que entra por la API pública

- **Estado:** Aceptado
- **Fecha:** 2026-11-16 (migra el ADR-06 de `Arquitectura.md`)
- **Decisores:** equipo CAUDAL
- **Drivers:** D-15, D-09, D-13, D-06
- **Decisión reemplaza a:** ADR-06 de `Arquitectura.md` §12 (formato corto)

## Contexto

- **No hay datos reales** de la región (RG-02, [`Datos-simulados.md`](../Datos-simulados.md) §1): ni niveles, ni lluvias, ni consumos.
- **D-15 (4, 2) Simulado ≠ real.** RNF-28, HU-38, HU-39 y RG-14: todo lo del acueducto demo se muestra como "Datos simulados", y la importación de historial **solo** funciona en acueductos `is_demo = true`.
- **D-09 (2, 4) Hardware real (diferido).** RNF-08 y HU-34 a HU-36: la telemetría firmada Ed25519 y los comandos de válvula deben estar listos para que un sensor real entre **sin cambiar el backend**, aunque el hardware no se construye (RG-12).
- **D-13 (4, 3) Calidad medible.** Para comparar la IA con la estimación simple hacen falta series **reproducibles** (misma semilla, mismo resultado) y una verdad de terreno que el backend nunca vea.
- **D-06 (4, 2) Costo.** El simulador no debe sumar costo de nube.

## Decisión

`caudal-simulador` es **un repositorio y un proceso propios** (Python 3.12, Typer, FastAPI y un tablero Vite/React), que **solo** habla con el backend por las mismas puertas que usaría la realidad:

- como **fontanero**, con JWT, en `/api/v1/readings`;
- como **dispositivo**, con firma Ed25519, en `/api/v1/devices/telemetry` y `/api/v1/devices/commands`;
- como **comunidad**, en `/api/v1/public/*`;
- como **importador**, en `/api/v1/imports/*`, solo en el acueducto demo.

No tiene acceso a la base de datos. La verdad de terreno no sale del simulador. Corre **local** (no se despliega): `caudal-sim tablero | live | demo` y, en el arranque local, `docker compose --profile sim up sim`. Los escenarios son YAML con semilla (`scenarios/normal-year.yaml`, `dry-year.yaml`, …). Del lado del backend, la importación verifica `is_demo` y deja el rastro en `sim.import_batches`; del lado del simulador, `DemoTargetGuard` se niega a escribir en un acueducto que no sea demo.

## Alternativas consideradas y descartadas

### Alternativa A: semilla de datos dentro del backend (migración Flyway o `CommandLineRunner` con datos de prueba)

- **Ventajas:** un solo repositorio y un solo proceso, los datos aparecen al arrancar y no hay credenciales del simulador que manejar.
- **Desventajas:** los datos simulados entrarían por **atajos** (SQL directo) y no por la cadena de validación, la idempotencia ni la firma de dispositivos, así que esas rutas no se ejercitarían. Una migración con datos de prueba corre también en producción (Neon), y la verdad de terreno quedaría al alcance del backend.
- **Motivo del descarte:** rompe **D-15** (datos simulados mezclados con la base real) y deja **D-09** sin probar: si el simulador no firma con Ed25519, nada garantiza que un sensor real funcione. El backend ya eliminó a propósito el sembrado de cuentas demo por la misma razón.

### Alternativa B: importar archivos CSV a mano

- **Ventajas:** es muy simple y permite usar datos de cualquier fuente.
- **Desventajas:** no reproduce el campo en vivo (lecturas tardías, fallas de sensor, fontanero sin señal, comandos de válvula) y no es reproducible por semilla.
- **Motivo del descarte:** no sirve para **D-13** (sin una verdad de terreno controlada no se puede evaluar la IA) ni para demostrar el flujo completo en la sustentación.

### Alternativa C: simulador como módulo Java dentro del backend

- **Ventajas:** un solo stack y un solo build.
- **Desventajas:** acopla el modelo físico del tanque (balance de masa, lluvia, fugas) al despliegue de producción y usa memoria de la instancia gratuita. Además saca al integrante de datos de su stack (Python).
- **Motivo del descarte:** costo en **D-06** (memoria de Render free) y riesgo de que el código de simulación llegue a producción.

## Consecuencias

- **Positivas:** cada lectura simulada pasa por la misma validación, idempotencia y auditoría que una real. El protocolo de dispositivos queda probado de punta a punta (D-09). Las series son reproducibles para el backtest (D-13) y no hay costo de nube (D-06).
- **Negativas / costo:** hay un proceso y un repositorio más, credenciales del simulador que crear en cada entorno (la Junta crea las cuentas, no hay sembrado) y un costo de integración cuando cambia el contrato de la API (RG-09).
- **Riesgos y mitigaciones:**
  - *Importar en un acueducto real* → doble guardia: `DemoTargetGuard` en el simulador e `is_demo` en el backend (`ImportIT`).
  - *Contrato desalineado* → el OpenAPI del backend es el contrato (RG-09).
- **Seguimiento:** cuando exista hardware real, el simulador queda como herramienta de pruebas (`Datos-simulados.md` §10).

## Evidencia

- Código: `caudal-simulador/src/caudal_sim/{cli,api_client,signing,demo_guard,backfill,live}.py`, `caudal-simulador/scenarios/*.yaml`, `src/main/java/co/caudal/application/simulation/ImportHistoryCommand.java`, `src/main/java/co/caudal/infrastructure/device/DeviceTelemetryAdapter.java`.
- Pruebas: `caudal-simulador/tests/test_reproducibility.py`, `test_signing.py`, `test_demo_guard.py`, `test_import_safety.py`; backend `src/test/java/co/caudal/api/controller/ImportIT.java` (`aRealAqueductIsDemoOnlyAndAnOperatorCannotImport`), `src/test/java/co/caudal/infrastructure/device/DeviceTelemetryAdapterTest.java`.
- Comando de verificación: en `caudal-simulador`, `uv run pytest -q`; en el backend, `./mvnw -B -ntp verify -Dtest=NONE -Dsurefire.failIfNoSpecifiedTests=false -Dit.test=ImportIT`. Resultados en [`Evidencias-verificacion.md`](../Evidencias-verificacion.md).
