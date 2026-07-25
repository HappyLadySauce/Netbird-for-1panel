#!/usr/bin/env bash
# Safely update the NetBird server and Dashboard images used by a 1Panel instance.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
DEFAULT_APP_DIR="$(dirname "${SCRIPT_DIR}")"

APP_DIR="${NETBIRD_APP_DIR:-${DEFAULT_APP_DIR}}"
BACKUP_DIR="${NETBIRD_BACKUP_DIR:-/opt/1panel/backup/netbird-auto}"
LOCK_FILE="${NETBIRD_UPDATE_LOCK_FILE:-/tmp/netbird-auto-update.lock}"
STARTUP_WAIT="${NETBIRD_UPDATE_STARTUP_WAIT:-15}"
STRICT_HEALTHCHECK="${NETBIRD_UPDATE_STRICT_HEALTHCHECK:-0}"
DRY_RUN=0
NO_BACKUP=0
PULL_ONLY=0

usage() {
    cat <<'EOF'
Usage: auto-update.sh [options]

Options:
  --app-dir DIR       1Panel NetBird instance directory
  --backup-dir DIR    Backup destination
  --startup-wait SEC  Seconds to wait before checking containers (default: 15)
  --no-backup         Update without creating a stopped-state backup
  --pull-only         Pull images without recreating containers
  --dry-run           Validate and print the intended operation only
  -h, --help          Show this help

Environment variables with matching NETBIRD_* names can also configure the script.
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

log() { printf '[netbird-auto-update] %s\n' "$*"; }
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

SERVICES=(netbird-server dashboard)
IMAGES=(netbirdio/netbird-server:latest netbirdio/dashboard:latest)

container_image_id() {
    local service="$1" container_id
    container_id="$("${COMPOSE[@]}" ps -q "${service}" 2>/dev/null || true)"
    [[ -n "${container_id}" ]] || return 0
    docker inspect --format '{{.Image}}' "${container_id}" 2>/dev/null || true
}

container_version() {
    local service="$1" container_id label log_version image_id
    container_id="$("${COMPOSE[@]}" ps -q "${service}" 2>/dev/null || true)"
    [[ -n "${container_id}" ]] || return 0
    label="$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' \
        "${container_id}" 2>/dev/null || true)"
    if [[ "${label}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-].*)?$ ]]; then
        printf '%s\n' "${label}"
        return 0
    fi
    if [[ "${service}" == "netbird-server" ]]; then
        log_version="$(docker logs --tail 500 "${container_id}" 2>&1 \
            | sed -nE 's/.*management server version ([^[:space:]]+).*/\1/p' \
            | tail -n 1)"
        if [[ -n "${log_version}" ]]; then
            printf '%s\n' "${log_version}"
            return 0
        fi
    fi
    image_id="$(docker inspect --format '{{.Image}}' "${container_id}" 2>/dev/null || true)"
    printf 'image %.12s\n' "${image_id#sha256:}"
}

image_id() {
    docker image inspect --format '{{.Id}}' "$1" 2>/dev/null || true
}

verify_service() {
    local service="$1" container_id status
    container_id="$("${COMPOSE[@]}" ps -q "${service}" 2>/dev/null || true)"
    [[ -n "${container_id}" ]] || fail "Service ${service} has no container after update"
    status="$(docker inspect --format '{{.State.Status}}' "${container_id}")"
    if [[ "${status}" != "running" ]]; then
        "${COMPOSE[@]}" logs --tail 100 "${service}" >&2 || true
        fail "Service ${service} is ${status}, expected running"
    fi
}

log "App directory: ${APP_DIR}"
log "Current server version: $(container_version netbird-server)"
log "Current dashboard version: $(container_version dashboard)"

if ((DRY_RUN)); then
    log "Dry run: would pull ${IMAGES[*]}"
    log "Dry run: changed images would trigger backup to ${BACKUP_DIR} and Compose recreation"
    "${COMPOSE[@]}" config --services
    exit 0
fi

RUNNING_IMAGE_IDS=()
for service in "${SERVICES[@]}"; do
    RUNNING_IMAGE_IDS+=("$(container_image_id "${service}")")
done

log "Pulling current image tags ..."
"${COMPOSE[@]}" pull

if ((PULL_ONLY)); then
    log "Images pulled; --pull-only requested, containers were not recreated."
    exit 0
fi

TARGET_IMAGE_IDS=()
needs_update=0
for index in "${!IMAGES[@]}"; do
    target_id="$(image_id "${IMAGES[${index}]}")"
    [[ -n "${target_id}" ]] || fail "Pulled image not found: ${IMAGES[${index}]}"
    TARGET_IMAGE_IDS+=("${target_id}")
    if [[ "${RUNNING_IMAGE_IDS[${index}]}" != "${target_id}" ]]; then
        needs_update=1
    fi
done

if ((needs_update == 0)); then
    log "Containers already use the current images."
    exit 0
fi

backup_file=""
stopped=0
restart_if_stopped() {
    local status=$?
    if ((status != 0 && stopped)); then
        log "Update failed after containers were stopped; attempting to start the Compose project."
        "${COMPOSE[@]}" up -d --remove-orphans || true
    fi
    exit "${status}"
}
trap restart_if_stopped EXIT

if ((NO_BACKUP == 0)); then
    mkdir -p "${BACKUP_DIR}"
    chmod 700 "${BACKUP_DIR}"
    backup_file="${BACKUP_DIR}/netbird-$(date '+%Y%m%d-%H%M%S').tar.gz"
    image_manifest="${backup_file%.tar.gz}.images.txt"

    {
        printf 'netbird-server\t%s\t%s\t%s\n' \
            "${IMAGES[0]}" "${RUNNING_IMAGE_IDS[0]}" "$(container_version netbird-server)"
        printf 'dashboard\t%s\t%s\t%s\n' \
            "${IMAGES[1]}" "${RUNNING_IMAGE_IDS[1]}" "$(container_version dashboard)"
    } > "${image_manifest}"
    chmod 600 "${image_manifest}"

    log "Stopping NetBird for a consistent SQLite backup ..."
    stopped=1
    "${COMPOSE[@]}" stop

    backup_paths=(data docker-compose.yml)
    [[ -f .env ]] && backup_paths+=(.env)
    tar -czf "${backup_file}" "${backup_paths[@]}"
    chmod 600 "${backup_file}"
    log "Backup created: ${backup_file}"
    log "Previous image IDs: ${image_manifest}"
fi

log "Recreating NetBird containers with the pulled images ..."
"${COMPOSE[@]}" up -d --remove-orphans
stopped=0

if ((STARTUP_WAIT > 0)); then
    sleep "${STARTUP_WAIT}"
fi

for service in "${SERVICES[@]}"; do
    verify_service "${service}"
done

issuer="$(awk '$1 == "issuer:" { gsub(/"/, "", $2); print $2; exit }' data/config.yaml 2>/dev/null || true)"
if [[ -n "${issuer}" ]] && command -v curl >/dev/null 2>&1; then
    if curl -fsSk --max-time 15 "${issuer}/.well-known/openid-configuration" >/dev/null; then
        log "OIDC endpoint check passed: ${issuer}"
    elif [[ "${STRICT_HEALTHCHECK}" == "1" ]]; then
        fail "OIDC endpoint check failed: ${issuer}"
    else
        log "WARNING: containers are running, but the OIDC endpoint check failed: ${issuer}"
    fi
fi

log "Updated server version: $(container_version netbird-server)"
log "Updated dashboard version: $(container_version dashboard)"
[[ -n "${backup_file}" ]] && log "Rollback data backup: ${backup_file}"
log "Update completed."
