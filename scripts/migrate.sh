#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/.env" ] && export $(grep -v '^#' "$ROOT/.env" | xargs)

ACTION="${1:-up}"
: "${DATABASE_URL:=postgres://localhost/cloudelog_dev}"

# dbmate requires sslmode for localhost; strip any existing and force disable.
if echo "$DATABASE_URL" | grep -qE "localhost|127\.0\.0\.1"; then
  DATABASE_URL=$(echo "$DATABASE_URL" | sed 's/[?&]sslmode=[^&]*//')
  DATABASE_URL="${DATABASE_URL}?sslmode=disable"
fi

# dbmate writes schema.sql to the repo's db/ directory.
exec dbmate \
  -d "$ROOT/backend/dbmate/migrations" \
  --schema-file "$ROOT/db/schema.sql" \
  --url "$DATABASE_URL" \
  "$ACTION"
