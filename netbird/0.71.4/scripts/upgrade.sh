#!/bin/bash
# Pull newer images; config in ./data is preserved.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
cd "${BASE_DIR}"
if docker compose version >/dev/null 2>&1; then
    docker compose pull
elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose pull
else
    echo "[netbird-upgrade] docker compose not found" >&2
    exit 1
fi
echo "[netbird-upgrade] Images updated. Restart the app from 1Panel."
echo "[netbird-upgrade] See https://docs.netbird.io/selfhosted/maintenance/update"
