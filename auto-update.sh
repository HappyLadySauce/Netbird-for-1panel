#!/usr/bin/env bash
# Update a remote NetBird Relay first, then the local NetBird control plane.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_UPDATE_SCRIPT="${SCRIPT_DIR}/Netbird/0.71.4/scripts/auto-update.sh"
RELAY_UPDATE_SCRIPT="${SCRIPT_DIR}/NetbirdRelay/latest/scripts/auto-update.sh"

LOCAL_APP_DIR="${NETBIRD_LOCAL_APP_DIR:-/opt/1panel/apps/local/Netbird/Netbird}"
LOCAL_BACKUP_DIR="${NETBIRD_LOCAL_BACKUP_DIR:-/opt/1panel/backup/netbird-auto}"

RELAY_SSH_HOST="${NETBIRD_RELAY_SSH_HOST:-}"
RELAY_SSH_USER="${NETBIRD_RELAY_SSH_USER:-root}"
RELAY_SSH_PORT="${NETBIRD_RELAY_SSH_PORT:-22}"
RELAY_SSH_IDENTITY_FILE="${NETBIRD_RELAY_SSH_IDENTITY_FILE:-}"
RELAY_APP_DIR="${NETBIRD_RELAY_REMOTE_APP_DIR:-/opt/1panel/apps/local/NetbirdRelay/NetbirdRelay}"
RELAY_BACKUP_DIR="${NETBIRD_RELAY_REMOTE_BACKUP_DIR:-/opt/1panel/backup/netbird-relay-auto}"

STARTUP_WAIT="${NETBIRD_UPDATE_STARTUP_WAIT:-15}"
UPDATE_ORDER="${NETBIRD_UPDATE_ORDER:-relay-first}"
RUN_LOCAL=1
RUN_RELAY=1
DRY_RUN=0
PULL_ONLY=0

usage() {
    cat <<'EOF'
Usage: auto-update.sh [options]

Updates a remote NetBird Relay over SSH and the local NetBird control plane.
The default order is Relay first, so a failed remote update prevents a partial
control-plane upgrade.

Options:
  --dry-run       Validate both targets without pulling or restarting
  --pull-only     Pull images on both targets without restarting
  --local-only    Update only the local NetBird control plane
  --relay-only    Update only the remote NetBird Relay
  -h, --help      Show this help

Required for remote Relay updates:
  NETBIRD_RELAY_SSH_HOST

Common environment variables:
  NETBIRD_RELAY_SSH_USER              default: root
  NETBIRD_RELAY_SSH_PORT              default: 22
  NETBIRD_RELAY_SSH_IDENTITY_FILE     optional private key path
  NETBIRD_LOCAL_APP_DIR               local 1Panel instance directory
  NETBIRD_RELAY_REMOTE_APP_DIR        remote 1Panel Relay instance directory
  NETBIRD_LOCAL_BACKUP_DIR            local backup directory
  NETBIRD_RELAY_REMOTE_BACKUP_DIR     remote backup directory
  NETBIRD_UPDATE_STARTUP_WAIT         default: 15 seconds
  NETBIRD_UPDATE_ORDER                relay-first or server-first
EOF
}

while (($#)); do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --pull-only)
            PULL_ONLY=1
            shift
            ;;
        --local-only)
            RUN_RELAY=0
            shift
            ;;
        --relay-only)
            RUN_LOCAL=0
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

log() { printf '[netbird-update-coordinator] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

((RUN_LOCAL || RUN_RELAY)) || fail "No update target selected"
[[ "${STARTUP_WAIT}" =~ ^[0-9]+$ ]] || fail "NETBIRD_UPDATE_STARTUP_WAIT must be a non-negative integer"
case "${UPDATE_ORDER}" in
    relay-first|server-first) ;;
    *) fail "NETBIRD_UPDATE_ORDER must be relay-first or server-first" ;;
esac

[[ -f "${LOCAL_UPDATE_SCRIPT}" ]] || fail "Local update script not found: ${LOCAL_UPDATE_SCRIPT}"
[[ -f "${RELAY_UPDATE_SCRIPT}" ]] || fail "Relay update script not found: ${RELAY_UPDATE_SCRIPT}"

validate_remote_value() {
    local name="$1" value="$2" pattern="$3"
    [[ "${value}" =~ ${pattern} ]] || fail "Invalid ${name}: ${value}"
}

run_local_update() {
    local args=(
        --app-dir "${LOCAL_APP_DIR}"
        --backup-dir "${LOCAL_BACKUP_DIR}"
        --startup-wait "${STARTUP_WAIT}"
    )
    ((DRY_RUN)) && args+=(--dry-run)
    ((PULL_ONLY)) && args+=(--pull-only)

    log "Updating local NetBird control plane ..."
    bash "${LOCAL_UPDATE_SCRIPT}" "${args[@]}"
}

run_relay_update() {
    [[ -n "${RELAY_SSH_HOST}" ]] || fail "NETBIRD_RELAY_SSH_HOST is required unless --local-only is used"
    validate_remote_value "Relay SSH host" "${RELAY_SSH_HOST}" '^[A-Za-z0-9._:-]+$'
    validate_remote_value "Relay SSH user" "${RELAY_SSH_USER}" '^[A-Za-z0-9._-]+$'
    validate_remote_value "Relay SSH port" "${RELAY_SSH_PORT}" '^[0-9]+$'
    ((10#${RELAY_SSH_PORT} >= 1 && 10#${RELAY_SSH_PORT} <= 65535)) \
        || fail "Relay SSH port must be between 1 and 65535"
    validate_remote_value "Relay app directory" "${RELAY_APP_DIR}" '^/[A-Za-z0-9._/-]+$'
    validate_remote_value "Relay backup directory" "${RELAY_BACKUP_DIR}" '^/[A-Za-z0-9._/-]+$'

    local ssh_args=(
        -p "${RELAY_SSH_PORT}"
        -o BatchMode=yes
        -o ConnectTimeout=15
        "${RELAY_SSH_USER}@${RELAY_SSH_HOST}"
    )
    if [[ -n "${RELAY_SSH_IDENTITY_FILE}" ]]; then
        [[ -f "${RELAY_SSH_IDENTITY_FILE}" ]] || fail "Relay SSH identity file not found: ${RELAY_SSH_IDENTITY_FILE}"
        ssh_args=(-i "${RELAY_SSH_IDENTITY_FILE}" "${ssh_args[@]}")
    fi

    local remote_args=(
        --app-dir "${RELAY_APP_DIR}"
        --backup-dir "${RELAY_BACKUP_DIR}"
        --startup-wait "${STARTUP_WAIT}"
    )
    ((DRY_RUN)) && remote_args+=(--dry-run)
    ((PULL_ONLY)) && remote_args+=(--pull-only)

    log "Updating Relay on ${RELAY_SSH_USER}@${RELAY_SSH_HOST}:${RELAY_SSH_PORT} ..."
    ssh "${ssh_args[@]}" bash -s -- "${remote_args[@]}" < "${RELAY_UPDATE_SCRIPT}"
}

if [[ "${UPDATE_ORDER}" == "relay-first" ]]; then
    ((RUN_RELAY)) && run_relay_update
    ((RUN_LOCAL)) && run_local_update
else
    ((RUN_LOCAL)) && run_local_update
    ((RUN_RELAY)) && run_relay_update
fi

log "All requested updates completed."
