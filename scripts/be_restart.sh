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
