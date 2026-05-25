#!/bin/sh
# Install NetBird + Traefik 1Panel local apps into 1Panel app store directory.
# 将 NetBird、Traefik 1Panel 本地应用一次性安装到 1Panel 应用商店目录。
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/HappyLadySauce/Netbird-for-1panel/main/install.sh | sh
#
# Or from a cloned repo:
#   sh install.sh

set -e

REPO_URL="${PANEL_1PANEL_REPO:-${NETBIRD_1PANEL_REPO:-${TRAEFIK_1PANEL_REPO:-https://github.com/HappyLadySauce/Netbird-for-1panel.git}}}"
BRANCH="${PANEL_1PANEL_BRANCH:-${NETBIRD_1PANEL_BRANCH:-${TRAEFIK_1PANEL_BRANCH:-main}}}"
CLONE_DIR="${PANEL_1PANEL_CACHE:-${NETBIRD_1PANEL_CACHE:-${TRAEFIK_1PANEL_CACHE:-/tmp/Netbird-for-1panel}}}"

# app_key:legacy_dir:SKIP_CLEANUP_ENV (legacy/skip empty allowed)
APP_SPECS="Netbird:netbird:NETBIRD_INSTALL_SKIP_CLEANUP Traefik::TRAEFIK_INSTALL_SKIP_CLEANUP"

SOURCE_DIR=""
PANEL_ROOT=""

log() { printf '[1panel-apps-install] %s\n' "$*" >&2; }
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

git_quiet() {
    "$@" >/dev/null 2>&1
}

parse_app_spec() {
    spec="$1"
    APP_KEY="${spec%%:*}"
    rest="${spec#*:}"
    LEGACY_KEY="${rest%%:*}"
    SKIP_ENV="${rest#*:}"
    if [ "${LEGACY_KEY}" = "${SKIP_ENV}" ]; then
        LEGACY_KEY=""
        SKIP_ENV="${rest}"
    fi
}

local_repo_complete() {
    repo_dir="$1"
    spec="$2"
    parse_app_spec "${spec}"
    [ -d "${repo_dir}/${APP_KEY}" ]
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

    for spec in ${APP_SPECS}; do
        parse_app_spec "${spec}"
        [ -d "${CLONE_DIR}/${APP_KEY}" ] || die "Clone succeeded but ${APP_KEY}/ is missing in ${CLONE_DIR}"
    done
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
        all_present=1
        for spec in ${APP_SPECS}; do
            if ! local_repo_complete "${script_dir}" "${spec}"; then
                all_present=0
                break
            fi
        done
        if [ "${all_present}" -eq 1 ]; then
            SOURCE_DIR="${script_dir}"
            return 0
        fi
    fi

    sync_git_repo
}

should_skip_cleanup() {
    skip_env_name="$1"
    if [ "${PANEL_INSTALL_SKIP_CLEANUP:-0}" = "1" ]; then
        return 0
    fi
    if [ -n "${skip_env_name}" ]; then
        eval "skip_val=\${${skip_env_name}:-0}"
        [ "${skip_val}" = "1" ] && return 0
    fi
    return 1
}

cleanup_local_app_catalog() {
    local_apps_dir="$1"
    target_dir="$2"
    legacy_key="$3"
    skip_env_name="$4"

    if should_skip_cleanup "${skip_env_name}"; then
        log "Skip cleanup for ${target_dir}"
        return 0
    fi

    if [ -n "${legacy_key}" ]; then
        stale="${local_apps_dir}/${legacy_key}"
        if [ -e "${stale}" ]; then
            log "Removing stale local app files: ${stale}"
            rm -rf "${stale}"
        fi
    fi
    if [ -e "${target_dir}" ]; then
        log "Removing stale local app files: ${target_dir}"
        rm -rf "${target_dir}"
    fi
}

install_app_from_dir() {
    src_dir="$1"
    app_key="$2"
    target_dir="$3"
    legacy_key="$4"
    skip_env_name="$5"

    [ -n "${src_dir}" ] || die "Source directory is empty"
    [ -d "${src_dir}/${app_key}" ] || die "App folder not found: ${src_dir}/${app_key}"

    cleanup_local_app_catalog "$(dirname "${target_dir}")" "${target_dir}" "${legacy_key}" "${skip_env_name}"

    mkdir -p "${target_dir}"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "${src_dir}/${app_key}/" "${target_dir}/"
    else
        rm -rf "${target_dir}"
        mkdir -p "${target_dir}"
        cp -a "${src_dir}/${app_key}/." "${target_dir}/"
    fi

    for scripts_dir in "${target_dir}"/*/scripts; do
        if [ -d "${scripts_dir}" ]; then
            chmod +x "${scripts_dir}"/*.sh 2>/dev/null || true
        fi
    done
}

resolve_panel_source() {
    if [ -n "${PANEL_1PANEL_SOURCE:-}" ]; then
        printf '%s\n' "${PANEL_1PANEL_SOURCE}"
        return 0
    fi
    if [ -n "${NETBIRD_1PANEL_SOURCE:-}" ]; then
        printf '%s\n' "${NETBIRD_1PANEL_SOURCE}"
        return 0
    fi
    if [ -n "${TRAEFIK_1PANEL_SOURCE:-}" ]; then
        printf '%s\n' "${TRAEFIK_1PANEL_SOURCE}"
        return 0
    fi
    return 1
}

main() {
    need_cmd mkdir
    need_cmd chmod

    detect_1panel_root || die \
        "1Panel local apps path not found. Set ONEPANEL_ROOT (e.g. export ONEPANEL_ROOT=/opt/1panel)"

    local_apps="${PANEL_ROOT}/resource/apps/local"

    panel_source=""
    panel_source=$(resolve_panel_source 2>/dev/null) || panel_source=""
    if [ -n "${panel_source}" ]; then
        for spec in ${APP_SPECS}; do
            parse_app_spec "${spec}"
            [ -d "${panel_source}/${APP_KEY}" ] || die "Source missing ${APP_KEY}/: ${panel_source}"
        done
        SOURCE_DIR="${panel_source}"
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

    for spec in ${APP_SPECS}; do
        parse_app_spec "${spec}"
        target="${local_apps}/${APP_KEY}"
        log "Installing ${APP_KEY} -> ${target}"
        install_app_from_dir "${SOURCE_DIR}" "${APP_KEY}" "${target}" "${LEGACY_KEY}" "${SKIP_ENV}"
    done

    log "Done."
    log "Open 1Panel -> App Store -> Update app list, then install NetBird and Traefik."
    log "NetBird OpenResty: ${local_apps}/Netbird/README.md and docs/openresty/1panel-openresty.md"
    log "Traefik: ${local_apps}/Traefik/README.md (Dashboard 127.0.0.1, HTTP/HTTPS default 8880/8443)"
    log "NetBird first admin: https://<your-domain>/setup"
}

main "$@"
