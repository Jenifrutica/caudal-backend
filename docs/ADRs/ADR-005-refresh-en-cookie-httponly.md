# ADR-005: Access token en memoria y refresh rotatorio en cookie `HttpOnly`

- **Estado:** Aceptado
- **Fecha:** 2026-11-16 (migra el ADR-04 de `Arquitectura.md`)
- **Decisores:** equipo CAUDAL
- **Drivers:** D-04, D-01
- **Decisión reemplaza a:** ADR-04 de `Arquitectura.md` §12 (formato corto)

## Contexto

- **D-04 (5, 3) Seguridad de cuentas.** RNF-02: JWT de **15 min**, refresh opaco hasheado que rota y **detecta reutilización**; RNF-11: nada sensible en `localStorage`. Escenario: si un atacante roba el token de acceso, le sirve como mucho 15 minutos, y si reutiliza un refresh ya rotado, **se revoca toda la familia** de sesiones.
- **D-01 (5, 4) Offline-first.** El fontanero trabaja días sin señal: su sesión debe durar (`REFRESH_TTL_DAYS_OPERATOR=30`) sin obligarlo a teclear la contraseña en el tanque. Si la sesión vence con lecturas pendientes, la app pide entrar de nuevo **sin borrar la cola** (RNF-14).
- Restricción de despliegue: la PWA (Vercel) y la API (Render) están en **sitios distintos**. La API es *stateless* y corre en una sola instancia gratuita que se duerme (RG-04).

## Decisión

- **Access token** JWT HS256 de 15 min, que el frontend guarda **solo en memoria** (`caudal-frontend/src/services/session/TokenStore.ts`). Recargar la página obliga a llamar a `/auth/refresh`.
- **Refresh token** opaco de 256 bits, guardado como **SHA-256** en `iam.refresh_tokens`, con **rotación** en cada uso y **detección de reutilización**: `RefreshTokenService` captura `RefreshTokenReuseException` y revoca la familia.
- Viaja en la cookie `caudal_rt` (`HttpOnly; Secure; Path=/api/v1/auth`), creada por `RefreshCookieFactory`. `SameSite` sale de `COOKIE_SAME_SITE`: `None` entre Vercel y Render, `Lax` en local.
- **Contra CSRF** con `SameSite=None`: `RefreshRequestGuard` exige la cabecera `X-Requested-With` y verifica `Origin` contra `CORS_ALLOWED_ORIGINS`.

## Alternativas consideradas y descartadas

### Alternativa A: access y refresh en `localStorage`

- **Ventajas:** es lo más simple de implementar, sobrevive a recargas sin llamar a la API y no tiene problemas de cookies entre sitios.
- **Desventajas:** cualquier XSS (una dependencia comprometida o un texto mal escapado) lee **ambos** tokens y se los lleva. El refresh robado da acceso por 30 días.
- **Motivo del descarte:** rompe **D-04** y RNF-11 directamente. El celular del fontanero puede ser compartido (RG-07), así que un token persistente legible por JavaScript es justo lo que no se quiere.

### Alternativa B: sesión en el servidor (cookie de sesión con estado en la API)

- **Ventajas:** revocación inmediata y el patrón clásico de Spring Security, sin tokens en el cliente.
- **Desventajas:** la API deja de ser *stateless*: hay que guardar sesiones en la BD o en memoria (y se pierden cuando Render duerme el servicio). Además, una cookie de sesión enviada en **todas** las peticiones entre sitios abre CSRF en toda la API, no solo en `/auth`.
- **Motivo del descarte:** el costo en **D-06** (estado en una instancia gratuita que se reinicia) y la superficie de CSRF mayor que con la cookie limitada a `Path=/api/v1/auth`. La revocación se logra igual con `token_version` en el JWT y la rotación del refresh.

### Alternativa C: JWT de larga duración (días) sin refresh

- **Ventajas:** no hace falta endpoint de refresh ni cookie, y funciona offline por días.
- **Desventajas:** un token robado vale días y no se puede revocar sin una lista negra.
- **Motivo del descarte:** contradice el JWT de **15 min** de RNF-02 (cifra canónica) y por tanto **D-04**.

## Consecuencias

- **Positivas:** un XSS no puede leer el refresh. El reuso de un refresh revoca la familia y la API sigue *stateless*. El fontanero mantiene la sesión 30 días (D-01).
- **Negativas / costo:** cada recarga hace un `/auth/refresh`. La configuración de cookies entre sitios es delicada (`SameSite=None` + `Secure` + CORS con credenciales) y en local hay que usar `COOKIE_SECURE=false` y `SameSite=Lax`.
- **Riesgos y mitigaciones:**
  - *Navegadores que bloquean cookies de terceros* → si la PWA y la API llegan a compartir dominio, se pasa a `SameSite=Strict`, que solo requiere cambiar la variable de entorno.
  - *Refresh vencido con lecturas pendientes* → la cola de IndexedDB no se borra (ADR-007) y la app pide volver a entrar.
- **Seguimiento:** se revisa cuando la PWA y la API compartan dominio propio.

## Evidencia

- Código: `src/main/java/co/caudal/api/security/{RefreshCookieFactory,RefreshRequestGuard}.java`, `src/main/java/co/caudal/application/auth/RefreshTokenService.java`, `src/main/java/co/caudal/infrastructure/security/Argon2PasswordHasherAdapter.java`, `caudal-frontend/src/services/session/TokenStore.ts`.
- Pruebas: `src/test/java/co/caudal/api/security/RefreshCookieTest.java`, `src/test/java/co/caudal/application/auth/RefreshTokenServiceTest.java`, `src/test/java/co/caudal/domain/session/RefreshTokenStateTest.java`.
- Comando de verificación: `./mvnw -q -Dtest='RefreshCookieTest,RefreshTokenServiceTest,RefreshTokenStateTest' test`. Resultado en [`Evidencias-verificacion.md`](../Evidencias-verificacion.md).
