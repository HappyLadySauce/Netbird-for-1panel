#!/usr/bin/env bash
# Safely update the NetBird Relay image used by a 1Panel instance.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
DEFAULT_APP_DIR="$(dirname "${SCRIPT_DIR}")"

APP_DIR="${NETBIRD_RELAY_APP_DIR:-${DEFAULT_APP_DIR}}"
BACKUP_DIR="${NETBIRD_RELAY_BACKUP_DIR:-/opt/1panel/backup/netbird-relay-auto}"
LOCK_FILE="${NETBIRD_RELAY_UPDATE_LOCK_FILE:-/tmp/netbird-relay-auto-update.lock}"
STARTUP_WAIT="${NETBIRD_UPDATE_STARTUP_WAIT:-15}"
STRICT_HEALTHCHECK="${NETBIRD_UPDATE_STRICT_HEALTHCHECK:-0}"
DRY_RUN=0
NO_BACKUP=0
PULL_ONLY=0

usage() {
    cat <<'EOF'
Usage: auto-update.sh [options]

Options:
  --app-dir DIR       1Panel NetBird Relay instance directory
  --backup-dir DIR    Backup destination
  --startup-wait SEC  Seconds to wait before checking the container (default: 15)
  --no-backup         Update without creating a stopped-state backup
  --pull-only         Pull the image without recreating the container
  --dry-run           Validate and print the intended operation only
  -h, --help          Show this help

Environment variables with matching NETBIRD_RELAY_* names can also configure the script.
EOF
}

while (($#)); do
    case "$1" in
        --app-dir)
            [[ $# -ge 2 ]] || { echo "--app-dir requires a value" >&2; exit 2; }
            APP_DIR="$2"
            shift 2
            ;;
        --backup-dir)
            [[ $# -ge 2 ]] || { echo "--backup-dir requires a value" >&2; exit 2; }
            BACKUP_DIR="$2"
            shift 2
            ;;
        --startup-wait)
            [[ $# -ge 2 ]] || { echo "--startup-wait requires a value" >&2; exit 2; }
            STARTUP_WAIT="$2"
            shift 2
            ;;
        --no-backup)
            NO_BACKUP=1
            shift
            ;;
        --pull-only)
            PULL_ONLY=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

log() { printf '[netbird-relay-auto-update] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

[[ "${STARTUP_WAIT}" =~ ^[0-9]+$ ]] || fail "startup wait must be a non-negative integer"
[[ -d "${APP_DIR}" ]] || fail "App directory not found: ${APP_DIR}"
[[ -f "${APP_DIR}/docker-compose.yml" ]] || fail "docker-compose.yml not found in ${APP_DIR}"
[[ -d "${APP_DIR}/data" ]] || fail "Data directory not found: ${APP_DIR}/data"

need_cmd docker
need_cmd flock
need_cmd tar

if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
else
    fail "docker compose not found"
fi

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    log "Another update is already running; skipping."
    exit 0
fi

cd "${APP_DIR}"

# 1Panel intentionally leaves HOST_IP empty when public port access is enabled.
export HOST_IP="${HOST_IP:-}"

container_id="$("${COMPOSE[@]}" ps -q relay 2>/dev/null || true)"
running_image_id=""
current_version=""
if [[ -n "${container_id}" ]]; then
    running_image_id="$(docker inspect --format '{{.Image}}' "${container_id}" 2>/dev/null || true)"
    current_version="$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' \
        "${container_id}" 2>/dev/null || true)"
fi
if [[ ! "${current_version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-].*)?$ ]]; then
    current_version="image ${running_image_id#sha256:}"
    current_version="${current_version:0:18}"
fi

log "App directory: ${APP_DIR}"
log "Current Relay version: ${current_version}"

if ((DRY_RUN)); then
    log "Dry run: would pull netbirdio/relay:latest"
    log "Dry run: a changed image would trigger backup to ${BACKUP_DIR} and Compose recreation"
    "${COMPOSE[@]}" config --services
    exit 0
fi

log "Pulling the current Relay image tag ..."
"${COMPOSE[@]}" pull relay

if ((PULL_ONLY)); then
    log "Image pulled; --pull-only requested, the container was not recreated."
    exit 0
fi

target_image_id="$(docker image inspect --format '{{.Id}}' netbirdio/relay:latest 2>/dev/null || true)"
[[ -n "${target_image_id}" ]] || fail "Pulled Relay image was not found"

if [[ "${running_image_id}" == "${target_image_id}" ]]; then
    log "The Relay container already uses the current image."
    exit 0
fi

backup_file=""
stopped=0
restart_if_stopped() {
    local status=$?
    if ((status != 0 && stopped)); then
        log "Update failed after the Relay was stopped; attempting to start the Compose project."
        "${COMPOSE[@]}" up -d --remove-orphans || true
    fi
    exit "${status}"
}
trap restart_if_stopped EXIT

if ((NO_BACKUP == 0)); then
    mkdir -p "${BACKUP_DIR}"
    chmod 700 "${BACKUP_DIR}"
    backup_file="${BACKUP_DIR}/netbird-relay-$(date '+%Y%m%d-%H%M%S').tar.gz"
    image_manifest="${backup_file%.tar.gz}.images.txt"
    printf 'relay\t%s\t%s\t%s\n' \
        'netbirdio/relay:latest' "${running_image_id}" "${current_version}" > "${image_manifest}"
    chmod 600 "${image_manifest}"

    log "Stopping the Relay for a consistent data backup ..."
    stopped=1
    "${COMPOSE[@]}" stop relay

    backup_paths=(data docker-compose.yml)
    [[ -f .env ]] && backup_paths+=(.env)
    tar -czf "${backup_file}" "${backup_paths[@]}"
    chmod 600 "${backup_file}"
    log "Backup created: ${backup_file}"
    log "Previous image ID: ${image_manifest}"
fi

log "Recreating the Relay container with the pulled image ..."
"${COMPOSE[@]}" up -d --remove-orphans relay
stopped=0

if ((STARTUP_WAIT > 0)); then
    sleep "${STARTUP_WAIT}"
fi

container_id="$("${COMPOSE[@]}" ps -q relay 2>/dev/null || true)"
[[ -n "${container_id}" ]] || fail "Relay has no container after update"
status="$(docker inspect --format '{{.State.Status}}' "${container_id}")"
if [[ "${status}" != "running" ]]; then
    "${COMPOSE[@]}" logs --tail 100 relay >&2 || true
    fail "Relay is ${status}, expected running"
fi

relay_address="$(sed -n 's/^NB_EXPOSED_ADDRESS=//p' data/relay.env 2>/dev/null | tail -n 1)"
if [[ -n "${relay_address}" ]] && command -v curl >/dev/null 2>&1; then
    relay_url="${relay_address/rels:\/\//https://}"
    if curl -ksS --max-time 15 -o /dev/null "${relay_url}"; then
        log "Relay TLS endpoint check passed: ${relay_address}"
    elif [[ "${STRICT_HEALTHCHECK}" == "1" ]]; then
        fail "Relay TLS endpoint check failed: ${relay_address}"
    else
        log "WARNING: the container is running, but the Relay TLS endpoint check failed: ${relay_address}"
    fi
fi

updated_version="$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' \
    "${container_id}" 2>/dev/null || true)"
if [[ ! "${updated_version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-].*)?$ ]]; then
    updated_image_id="$(docker inspect --format '{{.Image}}' "${container_id}" 2>/dev/null || true)"
    updated_version="image ${updated_image_id#sha256:}"
    updated_version="${updated_version:0:18}"
fi
log "Updated Relay version: ${updated_version}"
[[ -n "${backup_file}" ]] && log "Rollback data backup: ${backup_file}"
log "Update completed."
