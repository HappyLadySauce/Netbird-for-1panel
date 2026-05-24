#!/bin/bash
# Shared helpers for netbird 1Panel app scripts.
# 1Panel NetBird 应用脚本公共函数。

netbird_log() { echo "[netbird] $*"; }
netbird_fail() { netbird_log "ERROR: $*"; exit 1; }

netbird_base_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]:-$0}")" && pwd)"
    dirname "${script_dir}"
}

netbird_load_env() {
    local base_dir="$1"
    local f
    for f in "${base_dir}/.env" "${base_dir}/scripts/.env" "./.env"; do
        if [[ -f "${f}" ]]; then
            set -a
            # shellcheck disable=SC1090
            source "${f}"
            set +a
            netbird_log "Loaded env from ${f}"
            return 0
        fi
    done
    return 1
}

# Remove containers left from a previous failed install (same CONTAINER_NAME).
# 清理上次安装失败遗留的同名容器。
netbird_cleanup_stale_containers() {
    local name="${CONTAINER_NAME:-}"
    [[ -n "${name}" ]] || return 0
    if command -v docker >/dev/null 2>&1; then
        docker rm -f "${name}" "${name}-server" 2>/dev/null || true
    fi
}

netbird_tcp_port_taken() {
    local bind_ip="$1" port="$2"
    if command -v ss >/dev/null 2>&1; then
        ss -Hltn 2>/dev/null | awk '{print $4}' | grep -qx "${bind_ip}:${port}"
        return $?
    fi
    if command -v nc >/dev/null 2>&1; then
        nc -z "${bind_ip}" "${port}" >/dev/null 2>&1
        return $?
    fi
    return 1
}

netbird_udp_port_taken() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -Huln 2>/dev/null | awk '{print $4}' | grep -qE ":${port}$"
        return $?
    fi
    return 1
}

netbird_assert_ports_free() {
    local http_port="${PANEL_APP_PORT_HTTP:-8080}"
    local mgmt_port="${NETBIRD_MGMT_PORT:-8081}"
    local stun_port="${NETBIRD_STUN_PORT:-3478}"
    local busy=""

    netbird_tcp_port_taken "127.0.0.1" "${http_port}" && busy="${busy} Dashboard(127.0.0.1:${http_port})"
    netbird_tcp_port_taken "127.0.0.1" "${mgmt_port}" && busy="${busy} Management(127.0.0.1:${mgmt_port})"
    netbird_udp_port_taken "${stun_port}" && busy="${busy} STUN(UDP:${stun_port})"

    if [[ -n "${busy}" ]]; then
        netbird_fail "Port(s) already in use:${busy}. Stop the other service, change ports on the install form, or remove leftover containers: docker rm -f \"\${CONTAINER_NAME}\" \"\${CONTAINER_NAME}-server\""
    fi
}

# If pinned tag is missing locally (registry timeout), fall back to latest in .env.
# 镜像 tag 拉取失败时，若本地仅有 latest，则写入 .env 供 compose 使用。
netbird_ensure_image_tags_in_env() {
    local base_dir="$1"
    local env_file="${base_dir}/.env"
    local dash_tag="${NETBIRD_DASHBOARD_TAG:-v0.71.4}"
    local srv_tag="${NETBIRD_SERVER_TAG:-v0.71.4}"
    local dash_image="netbirdio/dashboard:${dash_tag}"
    local srv_image="netbirdio/netbird-server:${srv_tag}"

    command -v docker >/dev/null 2>&1 || return 0
    [[ -f "${env_file}" ]] || return 0

    if ! docker image inspect "${dash_image}" >/dev/null 2>&1 && docker image inspect "netbirdio/dashboard:latest" >/dev/null 2>&1; then
        dash_image="netbirdio/dashboard:latest"
        netbird_log "Using local dashboard:latest (tag ${dash_tag} not present)"
    fi
    if ! docker image inspect "${srv_image}" >/dev/null 2>&1 && docker image inspect "netbirdio/netbird-server:latest" >/dev/null 2>&1; then
        srv_image="netbirdio/netbird-server:latest"
        netbird_log "Using local netbird-server:latest (tag ${srv_tag} not present)"
    fi

    local tmp="${env_file}.netbird.tmp"
    grep -vE '^(NETBIRD_DASHBOARD_IMAGE|NETBIRD_SERVER_IMAGE)=' "${env_file}" 2>/dev/null > "${tmp}" || : > "${tmp}"
    printf 'NETBIRD_DASHBOARD_IMAGE=%s\nNETBIRD_SERVER_IMAGE=%s\n' "${dash_image}" "${srv_image}" >> "${tmp}"
    mv "${tmp}" "${env_file}"
}

netbird_compose_down() {
    local base_dir="$1"
    [[ -f "${base_dir}/docker-compose.yml" ]] || return 0
    if docker compose version >/dev/null 2>&1; then
        (cd "${base_dir}" && docker compose --env-file "${base_dir}/.env" down --remove-orphans 2>/dev/null) || true
    elif command -v docker-compose >/dev/null 2>&1; then
        (cd "${base_dir}" && docker-compose --env-file "${base_dir}/.env" down --remove-orphans 2>/dev/null) || true
    fi
    netbird_cleanup_stale_containers
}
