#!/usr/bin/env bash
set -e

BE_PORT="${CLOUDELOG_BE_PORT:-8081}"
FE_PORT="${CLOUDELOG_FE_PORT:-8011}"

for port in "$BE_PORT" "$FE_PORT"; do
  pids=$(lsof -ti :"$port" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "killing :$port (pids: $pids)"
    kill -9 $pids
  else
    echo ":$port is free"
  fi
done
