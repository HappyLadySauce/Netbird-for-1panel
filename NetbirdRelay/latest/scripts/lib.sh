#!/bin/bash
# Shared helpers for NetBird Relay 1Panel app scripts.
# 1Panel NetBird Relay 应用脚本公共函数。

relay_log() { echo "[netbird-relay] $*"; }
relay_fail() { relay_log "ERROR: $*"; exit 1; }

# Docker ports line for 1Panel: env keys must use PANEL_APP_PORT_* prefix so
# 「端口外部访问」 can open firewall; HOST_IP is empty (0.0.0.0) when checked, else 127.0.0.1.
# 1Panel 约定：PANEL_APP_PORT_* 供「端口外部访问」识别；HOST_IP 勾选时为空以绑定全网卡。
relay_compose_publish() {
    local host_port="$1" container_port="$2" proto="${3:-tcp}"
    if [[ "${proto}" == "udp" ]]; then
        printf '      - "${HOST_IP}%s:%s/udp"\n' "${host_port}" "${container_port}"
    else
        printf '      - "${HOST_IP}%s:%s"\n' "${host_port}" "${container_port}"
    fi
}

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
    local tls_mode="${NETBIRD_RELAY_TLS_MODE:-custom_cert}"
    local relay_port="${PANEL_APP_PORT_HTTP:-${NETBIRD_RELAY_PUBLIC_PORT:-443}}"
    local stun_port="${PANEL_APP_PORT_STUN:-${NETBIRD_STUN_PORT:-3478}}"
    local acme_port="${PANEL_APP_PORT_ACME:-80}"
    local busy=""

    case "${tls_mode}" in
        letsencrypt_builtin)
            relay_host_tcp_port_taken "${acme_port}" \
                && busy="${busy} ACME(HTTP:${acme_port})"
            relay_host_tcp_port_taken "${relay_port}" \
                && busy="${busy} Relay(TCP:${relay_port})"
            ;;
        custom_cert)
            relay_host_tcp_port_taken "${relay_port}" \
                && busy="${busy} Relay(TCP:${relay_port})"
            ;;
        *)
            relay_fail "Invalid NETBIRD_RELAY_TLS_MODE: ${tls_mode} (use custom_cert or letsencrypt_builtin)"
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
