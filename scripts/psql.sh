#!/usr/bin/env bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/.env" ] && export $(grep -v '^#' "$ROOT/.env" | xargs)
: "${DATABASE_URL:=postgres://localhost/cloudelog_dev}"
exec psql "$DATABASE_URL" "$@"
