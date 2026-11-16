#!/usr/bin/env bash
# Solo desarrollo y demostración: crea la primera cuenta BOARD_ADMIN del acueducto demo en la base
# LOCAL de docker compose. No forma parte de `make up` ni de ninguna migración: el backend no siembra
# cuentas a propósito (V47 solo crea la cuenta de sistema deshabilitada).
#
# Uso:  scripts/demo-admin.sh <usuario> "<Nombre completo>"
# - La contraseña se pide por teclado (no se muestra, no queda en el historial ni en argumentos).
# - Se guarda como Argon2id (m=19456 KiB, t=2, p=1) en formato PHC, el mismo que verifica la API.
# - La cuenta queda con must_change_password = true: en el primer ingreso se exige cambiarla (HU-02).
# Desde ahí, la Junta crea las demás cuentas por la PWA o la API (POST /api/v1/users y /memberships).
set -euo pipefail

username="${1:-}"
full_name="${2:-}"
if [[ ! "$username" =~ ^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$ ]] || (( ${#full_name} < 2 || ${#full_name} > 80 )); then
  echo "Uso: $0 <usuario> \"<Nombre completo>\"  (usuario: 3 a 32 caracteres a-z 0-9 . _ -)" >&2
  exit 2
fi

docker inspect caudal-db >/dev/null 2>&1 || { echo "demo-admin: el contenedor caudal-db no existe (make up)" >&2; exit 1; }

read -r -s -p "Contraseña (12 a 128 caracteres): " password; echo
read -r -s -p "Repítela: " again; echo
[[ "$password" == "$again" ]] || { echo "demo-admin: las contraseñas no coinciden" >&2; exit 1; }
(( ${#password} >= 12 && ${#password} <= 128 )) || { echo "demo-admin: largo inválido" >&2; exit 1; }
unset again

# Hash Argon2id con argon2-cffi en un contenedor efímero; la contraseña entra por stdin.
hash="$(printf '%s' "$password" | docker run --rm -i python:3.12-slim sh -c \
  'pip install -q --disable-pip-version-check --root-user-action=ignore argon2-cffi==23.1.0 >/dev/null 2>&1 &&
   python -c "import sys; from argon2 import PasswordHasher as H; print(H(time_cost=2, memory_cost=19456, parallelism=1, hash_len=32, salt_len=16).hash(sys.stdin.read()))"')"
unset password
[[ "$hash" == \$argon2id\$v=19\$m=19456,t=2,p=1\$* ]] || { echo "demo-admin: no se pudo calcular el hash" >&2; exit 1; }

docker exec -i caudal-db sh -c 'psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d caudal \
  -v username="$1" -v full_name="$2" -v hash="$3"' sh "$username" "$full_name" "$hash" <<'SQL'
BEGIN;
SELECT id AS aqueduct_id FROM org.aqueducts WHERE slug = 'vereda-demo' \gset
SELECT id AS system_id FROM iam.users WHERE username = 'caudal.system' \gset
INSERT INTO iam.users (username, full_name, password_hash, status, must_change_password, created_by)
VALUES (:'username', :'full_name', :'hash', 'ACTIVE', true, :'system_id')
RETURNING id AS user_id \gset
INSERT INTO iam.memberships (user_id, aqueduct_id, role_code, granted_by)
VALUES (:'user_id', :'aqueduct_id', 'BOARD_ADMIN', :'system_id');
COMMIT;
SQL
echo "demo-admin: cuenta '$username' creada como BOARD_ADMIN de vereda-demo (deberá cambiar la contraseña al entrar)."
