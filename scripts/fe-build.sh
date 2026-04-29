#!/usr/bin/env bash
# Build the frontend: compile elm.js and template index.html with a
# content-hash version so deployed clients always pull the fresh bundle
# instead of a cached one.
#
# Usage:
#   ./scripts/fe-build.sh              # dev build
#   ./scripts/fe-build.sh --optimize   # production build (matches deploy)
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/frontend"

ELM_FLAGS=""
if [ "${1:-}" = "--optimize" ]; then
    ELM_FLAGS="--optimize"
fi

elm make src/Main.elm $ELM_FLAGS --output=elm.js

VERSION=$(shasum -a 256 elm.js | cut -c1-12)
sed "s|__ELM_VERSION__|$VERSION|g" index.html.tpl > index.html
echo "frontend built (elm.js version: $VERSION)"
