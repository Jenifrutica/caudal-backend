# ADR-003: Pronóstico en un servicio externo con circuito y estimación simple

- **Estado:** Aceptado
- **Fecha:** 2026-11-16 (migra el ADR-05 de `Arquitectura.md`)
- **Decisores:** equipo CAUDAL
- **Drivers:** D-05, D-06, D-13
- **Decisión reemplaza a:** ADR-05 de `Arquitectura.md` §12 (formato corto)

## Contexto

- **D-05 (5, 3) La IA nunca bloquea la operación.** RNF-16 y RF-16: si la IA falla, tarda o su circuito está abierto, el sistema usa la estimación simple. Escenario: con la IA caída o dormida, el pronóstico responde con la estimación simple dentro del timeout (conexión **2 s**, lectura **10 s**) y, tras **5 fallos**, el circuito se abre **60 s**.
- **D-06 (4, 2) Costo ≈ 0.** Chronos necesita PyTorch. En Render free (**512 MB**), `chronos-2-small` llegó al tope de memoria y `chronos-bolt-tiny` con un hilo tuvo un **pico de 334 MiB** (RG-03, [`Stack-tecnologico.md`](../Stack-tecnologico.md#ia-caudal-ia)). El backend Java ya usa su propia memoria en otro servicio gratuito.
- **D-13 (4, 3) Calidad medible.** HU-33 y RF-33: el equipo compara la IA con la estimación simple (MAE, WQL, cobertura, *skill*). Para eso **las dos** predicciones deben existir para el mismo instante.
- Dato medido que pesa en la decisión ([`Modulo-IA.md`](../Modulo-IA.md) §9): sobre la serie simulada `normal-year`, **ningún modelo Chronos supera a la persistencia en MAE** (h3: 0,479 y 0,434 frente a 0,419), aunque sí calibran mejor el rango (cobertura de 0,76 y 0,73 frente a 0,49). Veredicto actual: `does_not_help`, porque son datos simulados (RG-02).

## Decisión

El pronóstico vive en **`caudal-ia`, un servicio FastAPI sin estado** (Python 3.12, Chronos, sin acceso a la BD), y el backend lo consume detrás de un **proxy con circuito y respaldo**:

- `ForecasterPort` (puerto) → `RemoteForecasterProxy` (P11 Proxy) → `IaForecastClientAdapter` (HTTP con `Authorization: Bearer`, timeouts `IA_CONNECT_TIMEOUT_MS` / `IA_READ_TIMEOUT_MS`).
- `CircuitBreakerState` (P18 State: cerrado, abierto y semiabierto) con umbrales configurables (`CIRCUIT_BREAKER_*`).
- Respaldo: `BaselineForecaster` con `NaivePersistenceStrategy` ("seguirá igual que hoy", con el rango empírico de cambios diarios).
- **Pronóstico en sombra:** `ShadowBaselineForecaster` guarda también la estimación simple cuando la IA sí responde (`fallback_reason = SHADOW_BASELINE`), para que M10 compare ambas (D-13).
- Despliegue de la IA: `caudal-ia/render.yaml`, servicio propio en Render free, con el modelo horneado en la imagen (`HF_HUB_OFFLINE=1`).

## Alternativas consideradas y descartadas

### Alternativa A: Chronos embebido en el backend (DJL u ONNX en la JVM, o un sidecar en el mismo contenedor)

- **Ventajas:** no hay llamada de red ni token de servicio, la latencia es menor y se despliega una pieza menos.
- **Desventajas:** carga PyTorch o un *runtime* ONNX en el mismo contenedor que la JVM. Chronos se publica para Python (`chronos-forecasting`), y llevarlo a Java exige convertir y mantener el modelo. Un fallo de memoria del modelo tumba también la API de lecturas y turnos.
- **Motivo del descarte:** rompe **D-06** y **D-05** a la vez. Con 512 MB por servicio, la JVM más el modelo no caben (el modelo solo ya pica en 334 MiB), y un OOM detendría toda la operación de la vereda. Además obliga al integrante de IA (RG-05) a trabajar en el stack Java.

### Alternativa B: solo la estimación simple, sin IA

- **Ventajas:** cero dependencias de ML, cero costo y cero latencia. Hoy gana en MAE sobre los datos simulados.
- **Desventajas:** su rango no está calibrado (cobertura h3 de **0,49** frente a la meta de 70–90 %). No hay manera de saber si un modelo ayudaría cuando haya lecturas reales, y se pierde un objetivo explícito del proyecto (pronóstico con IA, `Caudal.md` §3.1).
- **Motivo del descarte:** incumple **D-13**: sin la IA corriendo en sombra no hay datos para decidir con números si ayuda. La decisión ya se protege del resultado: si la evaluación real también dice `does_not_help`, basta con dejar el circuito abierto o vaciar `IA_SERVICE_URL`, y el sistema sigue igual. Por eso la estimación simple es **el respaldo** y no la única opción.

### Alternativa C: llamar a una API de pronóstico de terceros (servicio en la nube de pago)

- **Ventajas:** no hay que hospedar modelos y la calidad podría ser mayor.
- **Desventajas:** tiene costo por llamada, envía datos del acueducto a un tercero (RNF-20) y depende de una cuenta de pago.
- **Motivo del descarte:** rompe **D-06** (costo) y suma un riesgo de privacidad sin ganancia demostrada.

## Consecuencias

- **Positivas:** la operación nunca espera a la IA (D-05). La IA escala, se duerme y se reemplaza sin tocar el backend. La comparación IA contra estimación simple queda guardada en `ops.forecast_runs` (D-13). El equipo de IA trabaja en Python.
- **Negativas / costo:** hay un servicio más que desplegar, un token de servicio que rotar (`IA_SERVICE_TOKEN` e `IA_SERVICE_TOKEN_PREVIOUS`) y un arranque en frío en Render (la primera llamada usa el respaldo).
- **Riesgos y mitigaciones:**
  - *La IA no aporta* → el veredicto se publica tal cual (`does_not_help`) y se decide con lecturas reales.
  - *Varias instancias del backend con circuitos independientes* → el estado del circuito vive en memoria por instancia (Modulo-IA §7.4). Hoy hay **una** instancia; se revisa si se escala.
- **Seguimiento:** volver a correr el backtest (`python -m caudal_ia.evaluation`) cuando existan **≥ 30** evaluaciones con datos reales (`BACKTEST_MIN_EVALUATIONS`).

## Evidencia

- Código: `src/main/java/co/caudal/infrastructure/forecast/{RemoteForecasterProxy,IaForecastClientAdapter,CircuitBreakerState}.java`, `src/main/java/co/caudal/application/forecast/{BaselineForecaster,ShadowBaselineForecaster}.java`, `src/main/java/co/caudal/domain/forecast/NaivePersistenceStrategy.java`, `caudal-ia/src/caudal_ia/evaluation/backtest.py`, `caudal-ia/render.yaml`.
- Pruebas: `src/test/java/co/caudal/infrastructure/forecast/RemoteForecasterProxyTest.java`, `CircuitBreakerStateTest.java`, `src/test/java/co/caudal/application/forecast/ShadowBaselineForecasterTest.java`; en `caudal-ia`, `tests/evaluation/` y `tests/test_service_token.py`.
- Comando de verificación: `./mvnw -q -Dtest='RemoteForecasterProxyTest,CircuitBreakerStateTest,ShadowBaselineForecasterTest' test`; en `caudal-ia`, `uv run pytest -q`. Resultados en [`Evidencias-verificacion.md`](../Evidencias-verificacion.md).
