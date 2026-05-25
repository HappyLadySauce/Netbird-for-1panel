#!/bin/bash
# Pull newer netbirdio/relay image; ./data is preserved.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
cd "${BASE_DIR}"
if docker compose version >/dev/null 2>&1; then
    docker compose pull
elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose pull
else
    echo "[netbird-relay-upgrade] docker compose not found" >&2
    exit 1
fi
echo "[netbird-relay-upgrade] Images updated. Restart the app from 1Panel."
