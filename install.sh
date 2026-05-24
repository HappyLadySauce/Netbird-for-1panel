#!/bin/sh
# Install NetBird 1Panel local app into 1Panel app store directory.
# 将 NetBird 1Panel 本地应用安装到 1Panel 应用商店目录。
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/HappyLadySauce/Netbird-for-1panel/main/install.sh | sh
#
# Or from a cloned repo:
#   sh install.sh

set -e

REPO_URL="${NETBIRD_1PANEL_REPO:-https://github.com/HappyLadySauce/Netbird-for-1panel.git}"
BRANCH="${NETBIRD_1PANEL_BRANCH:-main}"
APP_KEY="netbird"
CLONE_DIR="${NETBIRD_1PANEL_CACHE:-/tmp/Netbird-for-1panel}"

log() { printf '[netbird-1panel-install] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

detect_1panel_root() {
    if [ -n "${ONEPANEL_ROOT:-}" ] && [ -d "${ONEPANEL_ROOT}/resource/apps/local" ]; then
        printf '%s' "${ONEPANEL_ROOT}"
        return 0
    fi
    for candidate in /opt/1panel /usr/local/1panel; do
        if [ -d "${candidate}/resource/apps/local" ]; then
            printf '%s' "${candidate}"
            return 0
        fi
    done
    return 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

install_from_dir() {
    src_dir="$1"
    target_dir="$2"

    [ -d "${src_dir}/${APP_KEY}" ] || die "App folder not found: ${src_dir}/${APP_KEY}"

    mkdir -p "${target_dir}"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "${src_dir}/${APP_KEY}/" "${target_dir}/"
    else
        rm -rf "${target_dir}"
        mkdir -p "${target_dir}"
        cp -a "${src_dir}/${APP_KEY}/." "${target_dir}/"
    fi

    if [ -d "${target_dir}/0.71.4/scripts" ]; then
        chmod +x "${target_dir}"/0.71.4/scripts/*.sh 2>/dev/null || true
    fi
}

resolve_source_dir() {
    script_path="$1"

    if [ -n "${script_path}" ]; then
        case "${script_path}" in
            /*) script_dir=$(dirname "${script_path}") ;;
            *) script_dir=$(cd "$(dirname "${script_path}")" && pwd) ;;
        esac
        if [ -d "${script_dir}/${APP_KEY}" ]; then
            printf '%s' "${script_dir}"
            return 0
        fi
    fi

    need_cmd git
    log "Cloning or updating ${REPO_URL} (branch ${BRANCH}) ..."
    if [ -d "${CLONE_DIR}/.git" ]; then
        git -C "${CLONE_DIR}" fetch origin "${BRANCH}" --depth 1 2>/dev/null \
            || git -C "${CLONE_DIR}" fetch origin "${BRANCH}"
        git -C "${CLONE_DIR}" checkout "${BRANCH}" 2>/dev/null \
            || git -C "${CLONE_DIR}" checkout -B "${BRANCH}" "origin/${BRANCH}"
        git -C "${CLONE_DIR}" pull --ff-only origin "${BRANCH}" 2>/dev/null \
            || git -C "${CLONE_DIR}" reset --hard "origin/${BRANCH}"
    else
        rm -rf "${CLONE_DIR}"
        git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${CLONE_DIR}" \
            || git clone --branch "${BRANCH}" "${REPO_URL}" "${CLONE_DIR}"
    fi

    [ -d "${CLONE_DIR}/${APP_KEY}" ] || die "Clone succeeded but ${APP_KEY}/ is missing"
    printf '%s' "${CLONE_DIR}"
}

main() {
    need_cmd mkdir
    need_cmd chmod

    panel_root=$(detect_1panel_root) || die \
        "1Panel local apps path not found. Set ONEPANEL_ROOT (e.g. export ONEPANEL_ROOT=/opt/1panel)"

    local_apps="${panel_root}/resource/apps/local"
    target="${local_apps}/${APP_KEY}"

    if [ -n "${NETBIRD_1PANEL_SOURCE:-}" ] && [ -d "${NETBIRD_1PANEL_SOURCE}/${APP_KEY}" ]; then
        source_dir="${NETBIRD_1PANEL_SOURCE}"
    else
        # curl | sh 时 $0 为 sh，无法定位仓库目录，走 git clone
        script_path="$0"
        case "${script_path}" in
            sh|dash|bash|ksh|zsh) script_path="" ;;
        esac
        source_dir=$(resolve_source_dir "${script_path}")
    fi

    log "1Panel root: ${panel_root}"
    log "Installing ${APP_KEY} -> ${target}"

    install_from_dir "${source_dir}" "${target}"

    log "Done."
    log "Open 1Panel -> App Store -> Update app list, then install NetBird."
    log "After install, configure OpenResty per: ${target}/README.md"
    log "First admin: https://<your-domain>/setup"
}

main "$@"
