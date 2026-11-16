#!/usr/bin/env bash
# Prueba de humo del arranque local: falla (código distinto de 0) si alguna pieza no responde.
# Uso: make smoke   (o scripts/smoke.sh core para solo db + api)
set -uo pipefail

mode="${1:-full}"
api="${API_URL:-http://localhost:8080}"
ia="${IA_URL:-http://localhost:8000}"
web="${WEB_URL:-http://localhost:8081}"
failures=0

check() { # nombre, comando que debe tener éxito
  local name="$1"; shift
  if out="$("$@" 2>&1)"; then
    printf 'OK    %-40s %s\n' "$name" "$out"
  else
    printf 'FALLA %-40s %s\n' "$name" "$out"
    failures=$((failures + 1))
  fi
}

body_has() { # url, texto esperado
  local body
  body="$(curl -fsS --max-time 15 "$1")" || { echo "sin respuesta"; return 1; }
  grep -q "$2" <<<"$body" || { echo "no contiene $2"; return 1; }
  echo "200, contiene $2"
}

status_is() { # url, código esperado, método opcional
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X "${3:-GET}" "$1")"
  [[ "$code" == "$2" ]] || { echo "HTTP $code (se esperaba $2)"; return 1; }
  echo "HTTP $code"
}

check "API /actuator/health"              body_has "$api/actuator/health" '"status":"UP"'
check "API /v3/api-docs"                  body_has "$api/v3/api-docs" '"openapi"'
check "API datos: /api/v1/meta/constraints" body_has "$api/api/v1/meta/constraints" '"password"'
check "API sin token: /api/v1/readings"   status_is "$api/api/v1/readings" 401
check "API acueducto ajeno: /public/schedule" status_is "$api/api/v1/public/no-existe/schedule" 404

if [[ "$mode" == "full" ]]; then
  check "IA /v1/health"                   body_has "$ia/v1/health" 'ok'
  check "IA sin token: POST /v1/forecasts" status_is "$ia/v1/forecasts" 401 POST
  check "PWA /"                           body_has "$web/" '<title>CAUDAL'
  check "PWA fallback SPA /a/vereda-demo" body_has "$web/a/vereda-demo" '<title>CAUDAL'
fi

echo
if (( failures > 0 )); then
  echo "smoke: $failures verificación(es) fallaron."
  exit 1
fi
echo "smoke: todas las verificaciones pasaron ($mode)."
