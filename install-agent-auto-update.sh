#!/usr/bin/env bash
# Install the NetBird agent update script and its systemd timer.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_NOW=0
TARGET_VERSION=""

usage() {
    cat <<'EOF'
Usage: install-agent-auto-update.sh [--run-now] [--version VERSION]

Installs and enables netbird-agent-update.timer. Use --run-now to execute one
update immediately. --version implies --run-now and pins only that invocation;
future timer runs continue to use the latest version available from APT.
EOF
}

while (($#)); do
    case "$1" in
        --run-now)
            RUN_NOW=1
            shift
            ;;
        --version)
            [[ $# -ge 2 ]] || { echo "--version requires a value" >&2; exit 2; }
            TARGET_VERSION="$2"
            RUN_NOW=1
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

[[ "${EUID}" -eq 0 ]] || { echo "Run this script as root" >&2; exit 1; }

install -m 0755 "${SCRIPT_DIR}/netbird-agent-auto-update.sh" \
    /usr/local/sbin/netbird-agent-auto-update
install -m 0644 "${SCRIPT_DIR}/systemd/netbird-agent-update.service" \
    /etc/systemd/system/netbird-agent-update.service
install -m 0644 "${SCRIPT_DIR}/systemd/netbird-agent-update.timer" \
    /etc/systemd/system/netbird-agent-update.timer

systemctl daemon-reload
systemctl enable --now netbird-agent-update.timer

if ((RUN_NOW)); then
    args=()
    [[ -n "${TARGET_VERSION}" ]] && args+=(--version "${TARGET_VERSION}")
    /usr/local/sbin/netbird-agent-auto-update "${args[@]}"
fi

systemctl --no-pager status netbird-agent-update.timer
