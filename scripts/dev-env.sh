#!/usr/bin/env bash
# Crea el .env de desarrollo local a partir de .env.example (solo si no existe).
# - Genera cada secreto con `openssl rand -base64 32` y nunca lo imprime.
# - Deja valores locales: PostgreSQL de docker compose sin TLS, cookie sin Secure, CORS de la PWA local.
# Solo para desarrollo. En producción las variables vienen del proveedor (Render, Neon, Vercel).
set -euo pipefail

cd "$(dirname "$0")/.."
env_file=".env"

if [[ -f "$env_file" ]]; then
  echo "dev-env: $env_file ya existe; no se modifica (bórralo para regenerarlo)."
  exit 0
fi

command -v openssl >/dev/null || { echo "dev-env: falta openssl" >&2; exit 1; }

umask 077
secret() { openssl rand -base64 32; }
db_port="${DB_HOST_PORT:-5432}"

# Pares CLAVE=valor que reemplazan la línea correspondiente de .env.example.
declare -A values=(
  [DATABASE_URL]="jdbc:postgresql://localhost:${db_port}/caudal?sslmode=disable"
  [DATABASE_USERNAME]="caudal_app"
  [DATABASE_PASSWORD]="$(secret)"
  [FLYWAY_URL]="jdbc:postgresql://localhost:${db_port}/caudal?sslmode=disable"
  [FLYWAY_USER]="caudal_migrator"
  [FLYWAY_PASSWORD]="$(secret)"
  [JWT_SECRET]="$(secret)"
  [JWT_ISSUER]="caudal-api-local"
  [JWT_AUDIENCE]="caudal-web-local"
  [COOKIE_SAME_SITE]="Lax"
  [COOKIE_SECURE]="false"
  [CORS_ALLOWED_ORIGINS]="http://localhost:8081,http://localhost:5173"
  [IA_SERVICE_URL]="http://localhost:8000"
  [IA_SERVICE_TOKEN]="$(secret)"
  [IP_HMAC_KEY]="$(secret)"
  [MFA_ENCRYPTION_KEY]="$(secret)"
  [MFA_KEY_ID]="local-v1"
  [API_DOCS_ENABLED]="true"
)

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
while IFS= read -r line || [[ -n "$line" ]]; do
  key="${line%%=*}"
  if [[ "$line" != \#* && "$line" == *=* && -n "${values[$key]+x}" ]]; then
    printf '%s=%s\n' "$key" "${values[$key]}"
    unset "values[$key]"
  else
    printf '%s\n' "$line"
  fi
done < .env.example > "$tmp"

{
  echo
  echo "# --- Solo arranque local (scripts/dev-env.sh) ---"
  echo "# Puerto de PostgreSQL en la máquina (cámbialo si 5432 ya está ocupado)."
  echo "DB_HOST_PORT=${db_port}"
} >> "$tmp"

if grep -v '^#' "$tmp" | grep -q 'cambia-esto-'; then
  echo "dev-env: quedaron marcadores sin reemplazar:" >&2
  grep -v '^#' "$tmp" | grep 'cambia-esto-' | cut -d= -f1 >&2
  exit 1
fi

mv "$tmp" "$env_file"
trap - EXIT
echo "dev-env: $env_file creado con secretos aleatorios (no se muestran)."
