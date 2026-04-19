#!/bin/bash
# Transfer the latest (or specified) dump file from the production host to
# the local machine. Run this on your local Mac.
#
# Host and remote directory come from .env. Set them before running, e.g.:
#
#   CLOUDELOG_PROD_HOST=root@161.35.125.40
#   CLOUDELOG_PROD_BACKUP_DIR=/root/cloudelog/backups
#
# Usage:
#   ./db-fetch-dump.sh                  # fetches the latest dump
#   ./db-fetch-dump.sh <filename>       # fetches a specific dump file

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/.env" ] && export $(grep -v '^#' "$ROOT/.env" | xargs)

if [ -z "${CLOUDELOG_PROD_HOST:-}" ] || [ -z "${CLOUDELOG_PROD_BACKUP_DIR:-}" ]; then
    echo "Error: set CLOUDELOG_PROD_HOST and CLOUDELOG_PROD_BACKUP_DIR in .env"
    exit 1
fi

LOCAL_DIR="$ROOT/backups"
mkdir -p "$LOCAL_DIR"

if [ -n "${1:-}" ]; then
    FILENAME="$1"
else
    echo "Finding latest dump on $CLOUDELOG_PROD_HOST ..."
    FILENAME=$(ssh "$CLOUDELOG_PROD_HOST" "ls -t $CLOUDELOG_PROD_BACKUP_DIR/*.dump 2>/dev/null | head -1 | xargs basename")
    if [ -z "$FILENAME" ]; then
        echo "Error: no dump files found on the host. Run db-dump-do.sh on the server first."
        exit 1
    fi
fi

echo "Downloading $FILENAME ..."
scp "$CLOUDELOG_PROD_HOST:$CLOUDELOG_PROD_BACKUP_DIR/$FILENAME" "$LOCAL_DIR/$FILENAME"
echo "Done: $LOCAL_DIR/$FILENAME"
