#!/bin/bash
# Restore a dump file into the local cloudelog dev database.
# Run this on your local Mac.
#
# Usage:
#   ./db-restore-local.sh                  # restores the latest dump in backups/
#   ./db-restore-local.sh <filename>       # restores a specific dump file

set -euo pipefail

LOCAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/backups"
DB_URL="postgres://$(whoami)@localhost/cloudelog_dev?sslmode=disable"

if [ -n "${1:-}" ]; then
    FILEPATH="$1"
    # If just a filename (no path), look in backups/
    if [ ! -f "$FILEPATH" ] && [ -f "$LOCAL_DIR/$FILEPATH" ]; then
        FILEPATH="$LOCAL_DIR/$FILEPATH"
    fi
else
    FILEPATH=$(ls -t "$LOCAL_DIR"/*.dump 2>/dev/null | head -1)
    if [ -z "$FILEPATH" ]; then
        echo "Error: no dump files found in $LOCAL_DIR"
        exit 1
    fi
fi

if [ ! -f "$FILEPATH" ]; then
    echo "Error: file not found: $FILEPATH"
    exit 1
fi

echo "Restoring $FILEPATH into local cloudelog_dev ..."
pg_restore --clean --if-exists --no-owner --no-acl -d "$DB_URL" "$FILEPATH"
echo "Done."
