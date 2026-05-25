#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
relay_load_env "${BASE_DIR}" || true
relay_log "uninstall: stopping compose and removing containers ..."
relay_compose_down "${BASE_DIR}"
if [[ "${REMOVE_DATA:-0}" == "1" ]]; then
    rm -rf "${BASE_DIR}/data"
    relay_log "uninstall: removed ${BASE_DIR}/data"
else
    relay_log "uninstall: data kept at ${BASE_DIR}/data (set REMOVE_DATA=1 to delete)"
fi
