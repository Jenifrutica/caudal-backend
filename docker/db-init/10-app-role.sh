#!/usr/bin/env bash
# Solo desarrollo local: crea el rol caudal_app con contraseña antes de que Flyway corra V1.
# V1 crea el rol solo si no existe (IF NOT EXISTS) y verifica que no tenga atributos elevados,
# así la API local se conecta como caudal_app y la RLS se aplica igual que en producción.
# En Neon la contraseña se fija fuera de git (consola o ALTER ROLE del operador).
# PostgreSQL ejecuta este script una sola vez, cuando el volumen de datos está vacío.
set -euo pipefail

if [[ -z "${APP_DB_PASSWORD:-}" ]]; then
  echo "10-app-role: APP_DB_PASSWORD vacío; caudal_app se creará sin contraseña en V1." >&2
  exit 0
fi

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=app_password="$APP_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE caudal_app LOGIN PASSWORD %L', :'app_password')
 WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'caudal_app')
\gexec
SQL
