#!/bin/bash
# Shared helpers for Traefik 1Panel app scripts.
# 1Panel Traefik 应用脚本公共函数。

traefik_log() { echo "[traefik] $*"; }
traefik_fail() { traefik_log "ERROR: $*"; exit 1; }

traefik_load_env() {
    local base_dir="$1"
    local f
    for f in "${base_dir}/.env" "${base_dir}/scripts/.env" "./.env"; do
        if [[ -f "${f}" ]]; then
            set -a
            # shellcheck disable=SC1090
            source "${f}"
            set +a
            traefik_log "Loaded env from ${f}"
            return 0
        fi
    done
    return 1
}

traefik_cleanup_stale_containers() {
    local name="${CONTAINER_NAME:-}"
    [[ -n "${name}" ]] || return 0
    if command -v docker >/dev/null 2>&1; then
        docker rm -f "${name}" 2>/dev/null || true
    fi
}

traefik_tcp_port_taken() {
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

traefik_host_port_taken() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -Hltn 2>/dev/null | awk '{print $4}' | grep -qE ":${port}$"
        return $?
    fi
    return 1
}

traefik_assert_ports_free() {
    local dash_bind="${TRAEFIK_DASHBOARD_BIND:-127.0.0.1}"
    local dash_port="${PANEL_APP_PORT_HTTP:-8088}"
    local http_port="${TRAEFIK_HTTP_PORT:-8880}"
    local https_port="${TRAEFIK_HTTPS_PORT:-8443}"
    local busy=""

    if [[ "${dash_bind}" == "0.0.0.0" || "${dash_bind}" == "::" ]]; then
        traefik_host_port_taken "${dash_port}" && busy="${busy} Dashboard(0.0.0.0:${dash_port})"
    else
        traefik_tcp_port_taken "${dash_bind}" "${dash_port}" && busy="${busy} Dashboard(${dash_bind}:${dash_port})"
    fi
    traefik_host_port_taken "${http_port}" && busy="${busy} HTTP(:${http_port})"
    traefik_host_port_taken "${https_port}" && busy="${busy} HTTPS(:${https_port})"

    if [[ -n "${busy}" ]]; then
        traefik_fail "Port(s) already in use:${busy}. Change ports on the install form or remove leftover container: docker rm -f \"\${CONTAINER_NAME}\""
    fi
}

traefik_compose_down() {
    local base_dir="$1"
    [[ -f "${base_dir}/docker-compose.yml" ]] || return 0
    if docker compose version >/dev/null 2>&1; then
        (cd "${base_dir}" && docker compose --env-file "${base_dir}/.env" down --remove-orphans 2>/dev/null) || true
    elif command -v docker-compose >/dev/null 2>&1; then
        (cd "${base_dir}" && docker-compose --env-file "${base_dir}/.env" down --remove-orphans 2>/dev/null) || true
    fi
    traefik_cleanup_stale_containers
}
