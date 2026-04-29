#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FE_PORT="${CLOUDELOG_FE_PORT:-8011}"

echo "=== Stopping frontend on :$FE_PORT ==="
kill -9 $(lsof -ti :$FE_PORT) 2>/dev/null && echo "stopped" || echo "not running"

echo "=== Building frontend ==="
"$ROOT/scripts/fe-build.sh"
cd "$ROOT/frontend"

echo "=== Starting frontend on :$FE_PORT ==="
PORT="$FE_PORT" python3 serve.py > "$ROOT/frontend/run.log" 2>&1 &
sleep 1
echo "frontend pid: $! — logs in frontend/run.log"
