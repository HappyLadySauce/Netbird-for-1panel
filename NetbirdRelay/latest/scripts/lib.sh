#!/bin/bash
# Shared helpers for NetBird Relay 1Panel app scripts.
# 1Panel NetBird Relay 应用脚本公共函数。

relay_log() { echo "[netbird-relay] $*"; }
relay_fail() { relay_log "ERROR: $*"; exit 1; }

relay_load_env() {
    local base_dir="$1"
    local f
    for f in "${base_dir}/.env" "${base_dir}/scripts/.env" "./.env"; do
        if [[ -f "${f}" ]]; then
            set -a
            # shellcheck disable=SC1090
            source "${f}"
            set +a
            relay_log "Loaded env from ${f}"
            return 0
        fi
    done
    return 1
}

relay_cleanup_stale_containers() {
    local name="${CONTAINER_NAME:-}"
    [[ -n "${name}" ]] || return 0
    if command -v docker >/dev/null 2>&1; then
        docker rm -f "${name}" 2>/dev/null || true
    fi
}

relay_tcp_port_taken() {
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

relay_udp_port_taken() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -Huln 2>/dev/null | awk '{print $4}' | grep -qE ":${port}$"
        return $?
    fi
    return 1
}

relay_host_tcp_port_taken() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -Hltn 2>/dev/null | awk '{print $4}' | grep -qE ":${port}$"
        return $?
    fi
    return 1
}

relay_assert_ports_free() {
    local tls_mode="${NETBIRD_RELAY_TLS_MODE:-openresty_cert}"
    local local_port="${NETBIRD_RELAY_LOCAL_PORT:-33080}"
    local stun_port="${NETBIRD_STUN_PORT:-3478}"
    local busy=""

    case "${tls_mode}" in
        letsencrypt_builtin)
            relay_host_tcp_port_taken "80" && busy="${busy} HTTP(:80)"
            relay_host_tcp_port_taken "443" && busy="${busy} HTTPS(:443)"
            ;;
        openresty_cert|custom_cert)
            relay_tcp_port_taken "127.0.0.1" "${local_port}" && busy="${busy} Relay(127.0.0.1:${local_port})"
            ;;
        *)
            relay_fail "Invalid NETBIRD_RELAY_TLS_MODE: ${tls_mode} (use openresty_cert, letsencrypt_builtin, or custom_cert)"
            ;;
    esac

    relay_udp_port_taken "${stun_port}" && busy="${busy} STUN(UDP:${stun_port})"

    if [[ -n "${busy}" ]]; then
        relay_fail "Port(s) already in use:${busy}. Change ports on the install form or: docker rm -f \"\${CONTAINER_NAME}\""
    fi
}

relay_compose_down() {
    local base_dir="$1"
    [[ -f "${base_dir}/docker-compose.yml" ]] || return 0
    if docker compose version >/dev/null 2>&1; then
        (cd "${base_dir}" && docker compose --env-file "${base_dir}/.env" down --remove-orphans 2>/dev/null) || true
    elif command -v docker-compose >/dev/null 2>&1; then
        (cd "${base_dir}" && docker-compose --env-file "${base_dir}/.env" down --remove-orphans 2>/dev/null) || true
    fi
    relay_cleanup_stale_containers
}

relay_panel_root() {
    if [[ -n "${ONEPANEL_ROOT:-}" && -d "${ONEPANEL_ROOT}/www/sites" ]]; then
        printf '%s\n' "${ONEPANEL_ROOT}"
        return 0
    fi
    for candidate in /opt/1panel /usr/local/1panel; do
        if [[ -d "${candidate}/www/sites" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}
