#!/usr/bin/env bash
# Back up and update the NetBird Linux agent from its configured APT repository.

set -Eeuo pipefail

BACKUP_DIR="${NETBIRD_AGENT_BACKUP_DIR:-/var/backups/netbird-agent}"
KEEP_BACKUPS="${NETBIRD_AGENT_KEEP_BACKUPS:-5}"
LOCK_FILE="${NETBIRD_AGENT_LOCK_FILE:-/run/lock/netbird-agent-update.lock}"
TARGET_VERSION="${NETBIRD_AGENT_VERSION:-}"

usage() {
    cat <<'EOF'
Usage: netbird-agent-auto-update.sh [--version VERSION]

Without --version, updates the NetBird Linux agent to the newest version in
the configured APT repository. Existing or newer versions are left unchanged.

Environment variables:
  NETBIRD_AGENT_BACKUP_DIR    default: /var/backups/netbird-agent
  NETBIRD_AGENT_KEEP_BACKUPS  default: 5
  NETBIRD_AGENT_LOCK_FILE     default: /run/lock/netbird-agent-update.lock
  NETBIRD_AGENT_VERSION       optional exact version, overridden by --version
EOF
}

while (($#)); do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || { echo "--version requires a value" >&2; exit 2; }
            TARGET_VERSION="$2"
            shift 2
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

log() { printf '[netbird-agent-update] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root"
[[ "${KEEP_BACKUPS}" =~ ^[1-9][0-9]*$ ]] || fail "NETBIRD_AGENT_KEEP_BACKUPS must be a positive integer"
if [[ -n "${TARGET_VERSION}" ]]; then
    [[ "${TARGET_VERSION}" =~ ^[0-9A-Za-z.+:~_-]+$ ]] || fail "Invalid target version: ${TARGET_VERSION}"
fi

for command in apt-cache apt-get dpkg dpkg-query flock systemctl tar; do
    command -v "${command}" >/dev/null 2>&1 || fail "Required command not found: ${command}"
done

install -d -m 0755 "$(dirname "${LOCK_FILE}")"
exec 9>"${LOCK_FILE}"
flock -n 9 || fail "Another NetBird agent update is already running"

dpkg-query -W -f='${Status}\n' netbird 2>/dev/null | grep -qx 'install ok installed' \
    || fail "The netbird APT package is not installed"

log "Refreshing APT package metadata ..."
apt-get update -o DPkg::Lock::Timeout=300

INSTALLED_VERSION="$(dpkg-query -W -f='${Version}' netbird)"
if [[ -n "${TARGET_VERSION}" ]]; then
    DESIRED_VERSION="${TARGET_VERSION}"
    apt-cache show "netbird=${DESIRED_VERSION}" >/dev/null 2>&1 \
        || fail "NetBird version ${DESIRED_VERSION} is not available from APT"
else
    DESIRED_VERSION="$(apt-cache policy netbird | awk '/Candidate:/ { print $2; exit }')"
    [[ -n "${DESIRED_VERSION}" && "${DESIRED_VERSION}" != "(none)" ]] \
        || fail "No NetBird candidate version is available from APT"
fi

log "Installed: ${INSTALLED_VERSION}; requested: ${DESIRED_VERSION}"
if dpkg --compare-versions "${INSTALLED_VERSION}" ge "${DESIRED_VERSION}"; then
    log "No update required."
    exit 0
fi

umask 077
install -d -m 0700 "${BACKUP_DIR}"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
SAFE_VERSION="${INSTALLED_VERSION//[^0-9A-Za-z._+-]/_}"
BACKUP_FILE="${BACKUP_DIR}/netbird-agent-${SAFE_VERSION}-${TIMESTAMP}.tar.gz"

BACKUP_PATHS=()
[[ -d /etc/netbird ]] && BACKUP_PATHS+=(etc/netbird)
[[ -d /var/lib/netbird ]] && BACKUP_PATHS+=(var/lib/netbird)
((${#BACKUP_PATHS[@]} > 0)) || fail "Neither /etc/netbird nor /var/lib/netbird exists"

log "Backing up agent state to ${BACKUP_FILE} ..."
tar -C / -czf "${BACKUP_FILE}" "${BACKUP_PATHS[@]}"
chmod 0600 "${BACKUP_FILE}"

mapfile -d '' OLD_BACKUPS < <(
    find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'netbird-agent-*.tar.gz' \
        -printf '%T@ %p\0' | sort -zrn | tail -z -n "+$((KEEP_BACKUPS + 1))"
)
for entry in "${OLD_BACKUPS[@]}"; do
    rm -f -- "${entry#* }"
done

log "Installing NetBird ${DESIRED_VERSION} ..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -o DPkg::Lock::Timeout=300 \
    --only-upgrade "netbird=${DESIRED_VERSION}"

UPDATED_VERSION="$(dpkg-query -W -f='${Version}' netbird)"
[[ "${UPDATED_VERSION}" == "${DESIRED_VERSION}" ]] \
    || fail "Expected ${DESIRED_VERSION}, but ${UPDATED_VERSION} is installed"

for _ in {1..30}; do
    systemctl is-active --quiet netbird && break
    sleep 1
done
systemctl is-active --quiet netbird || fail "netbird.service is not active after the update"

log "Update completed: ${INSTALLED_VERSION} -> ${UPDATED_VERSION}"
