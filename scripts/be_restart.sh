#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Project isolation: ignore any inherited DATABASE_URL/JWT_* from the shell
# so we can't accidentally run the backend against another project's DB.
# The project's .env (if present) or the defaults below are the only sources.
unset DATABASE_URL JWT_SECRET JWT_EXPIRY_DAYS

[ -f "$ROOT/.env" ] && export $(grep -v '^#' "$ROOT/.env" | xargs)

: "${DATABASE_URL:=postgres://localhost/cloudelog_dev?sslmode=disable}"
: "${JWT_SECRET:=dev-secret-change-in-production-min-32-chars!!}"
: "${JWT_EXPIRY_DAYS:=30}"

# Production path: the droplet runs the backend under systemd from the
# installed binary at /usr/local/bin/cloudelog-backend. A `stack build` +
# `stack exec` here would only update the stack snapshot — systemd would
# keep relaunching the old installed binary. Update the installed binary
# and bounce the unit instead.
SYSTEMD_UNIT=/etc/systemd/system/cloudelog-backend.service
if [ -f "$SYSTEMD_UNIT" ] && command -v systemctl >/dev/null 2>&1; then
  echo "=== systemd unit detected at $SYSTEMD_UNIT — production restart path ==="
  echo "=== Installing backend binary to /usr/local/bin ==="
  cd "$ROOT/backend" && stack install --local-bin-path /usr/local/bin
  echo "=== Restarting cloudelog-backend via systemd ==="
  systemctl restart cloudelog-backend
  systemctl --no-pager status cloudelog-backend | head -n 15
  exit 0
fi

BE_PORT="${CLOUDELOG_BE_PORT:-8081}"

echo "=== Stopping backend on :$BE_PORT ==="
kill -9 $(lsof -ti :$BE_PORT) 2>/dev/null && echo "stopped" || echo "not running"

echo "=== Building backend ==="
cd "$ROOT/backend" && stack build

echo "=== Starting backend on :$BE_PORT ==="
cd "$ROOT/backend"
PORT="$BE_PORT" \
DATABASE_URL="$DATABASE_URL" \
JWT_SECRET="$JWT_SECRET" \
JWT_EXPIRY_DAYS="$JWT_EXPIRY_DAYS" \
  stack exec cloudelog-backend > "$ROOT/backend/run.log" 2>&1 &
sleep 2
echo "backend pid: $! — logs in backend/run.log"
