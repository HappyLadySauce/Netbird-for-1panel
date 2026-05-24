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

# Set by resolve_source_dir; do not capture via $(...) — git/log stdout would corrupt the path.
# 由 resolve_source_dir 赋值；勿用 $(...) 捕获，否则 git/log 输出会污染路径。
SOURCE_DIR=""
PANEL_ROOT=""

log() { printf '[netbird-1panel-install] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

detect_1panel_root() {
    if [ -n "${ONEPANEL_ROOT:-}" ] && [ -d "${ONEPANEL_ROOT}/resource/apps/local" ]; then
        PANEL_ROOT="${ONEPANEL_ROOT}"
        return 0
    fi
    for candidate in /opt/1panel /usr/local/1panel; do
        if [ -d "${candidate}/resource/apps/local" ]; then
            PANEL_ROOT="${candidate}"
            return 0
        fi
    done
    return 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

# Silence git progress on stdout (cron / 1Panel captures stdout).
# 禁止 git 向 stdout 输出，避免污染命令替换或任务日志解析。
git_quiet() {
    "$@" >/dev/null 2>&1
}

sync_git_repo() {
    need_cmd git
    log "Cloning or updating ${REPO_URL} (branch ${BRANCH}) ..."

    if [ -d "${CLONE_DIR}/.git" ]; then
        git_quiet git -C "${CLONE_DIR}" fetch origin "${BRANCH}" --depth 1 \
            || git_quiet git -C "${CLONE_DIR}" fetch origin "${BRANCH}"
        git_quiet git -C "${CLONE_DIR}" checkout "${BRANCH}" \
            || git_quiet git -C "${CLONE_DIR}" checkout -B "${BRANCH}" "origin/${BRANCH}"
        git_quiet git -C "${CLONE_DIR}" pull --ff-only origin "${BRANCH}" \
            || git_quiet git -C "${CLONE_DIR}" reset --hard "origin/${BRANCH}"
    else
        rm -rf "${CLONE_DIR}"
        git_quiet git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${CLONE_DIR}" \
            || git_quiet git clone --branch "${BRANCH}" "${REPO_URL}" "${CLONE_DIR}"
    fi

    [ -d "${CLONE_DIR}/${APP_KEY}" ] || die "Clone succeeded but ${APP_KEY}/ is missing in ${CLONE_DIR}"
    SOURCE_DIR="${CLONE_DIR}"
}

resolve_source_dir() {
    script_path="$1"
    SOURCE_DIR=""

    if [ -n "${script_path}" ]; then
        case "${script_path}" in
            /*) script_dir=$(dirname "${script_path}") ;;
            *) script_dir=$(cd "$(dirname "${script_path}")" && pwd) ;;
        esac
        if [ -d "${script_dir}/${APP_KEY}" ]; then
            SOURCE_DIR="${script_dir}"
            return 0
        fi
    fi

    sync_git_repo
}

install_from_dir() {
    src_dir="$1"
    target_dir="$2"

    [ -n "${src_dir}" ] || die "Source directory is empty"
    [ -d "${src_dir}/${APP_KEY}" ] || die "App folder not found: ${src_dir}/${APP_KEY}"

    mkdir -p "${target_dir}"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "${src_dir}/${APP_KEY}/" "${target_dir}/"
    else
        rm -rf "${target_dir}"
        mkdir -p "${target_dir}"
        cp -a "${src_dir}/${APP_KEY}/." "${target_dir}/"
    fi

    if [ -d "${target_dir}/latest/scripts" ]; then
        chmod +x "${target_dir}"/latest/scripts/*.sh 2>/dev/null || true
    fi
}

main() {
    need_cmd mkdir
    need_cmd chmod

    detect_1panel_root || die \
        "1Panel local apps path not found. Set ONEPANEL_ROOT (e.g. export ONEPANEL_ROOT=/opt/1panel)"

    local_apps="${PANEL_ROOT}/resource/apps/local"
    target="${local_apps}/${APP_KEY}"

    if [ -n "${NETBIRD_1PANEL_SOURCE:-}" ] && [ -d "${NETBIRD_1PANEL_SOURCE}/${APP_KEY}" ]; then
        SOURCE_DIR="${NETBIRD_1PANEL_SOURCE}"
    else
        script_path="$0"
        case "${script_path}" in
            sh|dash|bash|ksh|zsh) script_path="" ;;
        esac
        resolve_source_dir "${script_path}"
    fi

    [ -n "${SOURCE_DIR}" ] || die "Failed to resolve source directory"

    log "1Panel root: ${PANEL_ROOT}"
    log "Source: ${SOURCE_DIR}"
    log "Installing ${APP_KEY} -> ${target}"

    install_from_dir "${SOURCE_DIR}" "${target}"

    log "Done."
    log "Open 1Panel -> App Store -> Update app list, then install NetBird."
    log "After install, configure OpenResty per: ${target}/README.md"
    log "First admin: https://<your-domain>/setup"
}

main "$@"
