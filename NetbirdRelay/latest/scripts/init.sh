#!/bin/bash
# Generate NetBird external relay config for 1Panel (relay + embedded STUN only).
# 为 1Panel 生成 NetBird 外部 Relay/STUN 节点配置。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

BASE_DIR="$(dirname "${SCRIPT_DIR}")"
DATA_DIR="${BASE_DIR}/data"

log() { relay_log "init: $*"; }
fail() { relay_fail "$*"; }

validate_domain() {
    local d="${1:-}"
    [[ -n "$d" ]] || fail "NETBIRD_RELAY_DOMAIN is required"
    if [[ "$d" =~ ^https?:// ]]; then
        fail "NETBIRD_RELAY_DOMAIN must be hostname only (no http://)"
    fi
}

validate_port() {
    local name="$1" val="$2"
    [[ "$val" =~ ^[0-9]+$ ]] || fail "${name} must be a number"
    (( val >= 1 && val <= 65535 )) || fail "${name} must be between 1 and 65535"
}

validate_tls_mode() {
    local m="${1:-}"
    case "${m}" in
        openresty_cert|letsencrypt_builtin|custom_cert) ;;
        *) fail "NETBIRD_RELAY_TLS_MODE must be openresty_cert, letsencrypt_builtin, or custom_cert" ;;
    esac
}

relay_load_env "${BASE_DIR}" || true

NETBIRD_RELAY_DOMAIN="${NETBIRD_RELAY_DOMAIN:-}"
NETBIRD_RELAY_AUTH_SECRET="${NETBIRD_RELAY_AUTH_SECRET:-}"
NETBIRD_RELAY_TLS_MODE="${NETBIRD_RELAY_TLS_MODE:-openresty_cert}"
NETBIRD_RELAY_LOCAL_PORT="${NETBIRD_RELAY_LOCAL_PORT:-33080}"
NETBIRD_RELAY_PUBLIC_PORT="${NETBIRD_RELAY_PUBLIC_PORT:-443}"
NETBIRD_STUN_PORT="${NETBIRD_STUN_PORT:-3478}"
NETBIRD_LETSENCRYPT_EMAIL="${NETBIRD_LETSENCRYPT_EMAIL:-}"
NETBIRD_RELAY_CERT_DIR="${NETBIRD_RELAY_CERT_DIR:-}"
NETBIRD_TLS_CERT_FILE="${NETBIRD_TLS_CERT_FILE:-}"
NETBIRD_TLS_KEY_FILE="${NETBIRD_TLS_KEY_FILE:-}"

[[ -n "${NETBIRD_RELAY_DOMAIN}" ]] || fail "NETBIRD_RELAY_DOMAIN is required"
[[ -n "${NETBIRD_RELAY_AUTH_SECRET}" ]] || fail "NETBIRD_RELAY_AUTH_SECRET is required (copy authSecret from main NetBird config.yaml)"

validate_domain "${NETBIRD_RELAY_DOMAIN}"
validate_tls_mode "${NETBIRD_RELAY_TLS_MODE}"
validate_port "NETBIRD_RELAY_LOCAL_PORT" "${NETBIRD_RELAY_LOCAL_PORT}"
validate_port "NETBIRD_RELAY_PUBLIC_PORT" "${NETBIRD_RELAY_PUBLIC_PORT}"
validate_port "NETBIRD_STUN_PORT" "${NETBIRD_STUN_PORT}"

log "Cleaning up containers from any previous failed install ..."
relay_cleanup_stale_containers
relay_assert_ports_free

mkdir -p "${DATA_DIR}/relay-data"

NB_EXPOSED="rels://${NETBIRD_RELAY_DOMAIN}:${NETBIRD_RELAY_PUBLIC_PORT}"
RELAY_ENV_EXTRA=""
OVERRIDE_VOLUMES=""
CERT_HOST_DIR=""

case "${NETBIRD_RELAY_TLS_MODE}" in
    letsencrypt_builtin)
        [[ -n "${NETBIRD_LETSENCRYPT_EMAIL}" ]] || fail "NETBIRD_LETSENCRYPT_EMAIL is required for letsencrypt_builtin"
        NB_LISTEN=":443"
        RELAY_ENV_EXTRA=$(cat <<LEOF

NB_LETSENCRYPT_DOMAINS=${NETBIRD_RELAY_DOMAIN}
NB_LETSENCRYPT_EMAIL=${NETBIRD_LETSENCRYPT_EMAIL}
NB_LETSENCRYPT_DATA_DIR=/data/letsencrypt
LEOF
)
        cat > "${BASE_DIR}/docker-compose.override.yml" <<OEOF
services:
  relay:
    ports:
      - "${NETBIRD_STUN_PORT}:${NETBIRD_STUN_PORT}/udp"
      - "80:80"
      - "443:443"
    volumes:
      - ./data/relay-data:/data
OEOF
        ;;
    openresty_cert)
        NB_LISTEN=":${NETBIRD_RELAY_LOCAL_PORT}"
        panel_root=""
        panel_root="$(relay_panel_root 2>/dev/null || true)"
        if [[ -z "${NETBIRD_RELAY_CERT_DIR}" ]]; then
            if [[ -n "${panel_root}" ]]; then
                NETBIRD_RELAY_CERT_DIR="${panel_root}/www/sites/${NETBIRD_RELAY_DOMAIN}/ssl"
            else
                NETBIRD_RELAY_CERT_DIR="/opt/1panel/www/sites/${NETBIRD_RELAY_DOMAIN}/ssl"
            fi
        fi
        [[ -f "${NETBIRD_RELAY_CERT_DIR}/fullchain.pem" ]] || fail "Certificate not found: ${NETBIRD_RELAY_CERT_DIR}/fullchain.pem (create 1Panel HTTPS site first)"
        [[ -f "${NETBIRD_RELAY_CERT_DIR}/privkey.pem" ]] || fail "Private key not found: ${NETBIRD_RELAY_CERT_DIR}/privkey.pem"
        CERT_HOST_DIR="${NETBIRD_RELAY_CERT_DIR}"
        RELAY_ENV_EXTRA=$(cat <<OCEOF

NB_TLS_CERT_FILE=/certs/fullchain.pem
NB_TLS_KEY_FILE=/certs/privkey.pem
OCEOF
)
        cat > "${BASE_DIR}/docker-compose.override.yml" <<OEOF
services:
  relay:
    ports:
      - "${NETBIRD_STUN_PORT}:${NETBIRD_STUN_PORT}/udp"
      - "127.0.0.1:${NETBIRD_RELAY_LOCAL_PORT}:${NETBIRD_RELAY_LOCAL_PORT}"
    volumes:
      - ./data/relay-data:/data
      - ${CERT_HOST_DIR}:/certs:ro
OEOF
        ;;
    custom_cert)
        [[ -n "${NETBIRD_TLS_CERT_FILE}" && -f "${NETBIRD_TLS_CERT_FILE}" ]] || fail "NETBIRD_TLS_CERT_FILE must point to an existing file"
        [[ -n "${NETBIRD_TLS_KEY_FILE}" && -f "${NETBIRD_TLS_KEY_FILE}" ]] || fail "NETBIRD_TLS_KEY_FILE must point to an existing file"
        cert_dir="$(dirname "${NETBIRD_TLS_CERT_FILE}")"
        cert_base="$(basename "${NETBIRD_TLS_CERT_FILE}")"
        key_base="$(basename "${NETBIRD_TLS_KEY_FILE}")"
        NB_LISTEN=":${NETBIRD_RELAY_LOCAL_PORT}"
        CERT_HOST_DIR="${cert_dir}"
        RELAY_ENV_EXTRA=$(cat <<CCEOF

NB_TLS_CERT_FILE=/certs/${cert_base}
NB_TLS_KEY_FILE=/certs/${key_base}
CCEOF
)
        cat > "${BASE_DIR}/docker-compose.override.yml" <<OEOF
services:
  relay:
    ports:
      - "${NETBIRD_STUN_PORT}:${NETBIRD_STUN_PORT}/udp"
      - "127.0.0.1:${NETBIRD_RELAY_LOCAL_PORT}:${NETBIRD_RELAY_LOCAL_PORT}"
    volumes:
      - ./data/relay-data:/data
      - ${CERT_HOST_DIR}:/certs:ro
OEOF
        ;;
esac

cat > "${DATA_DIR}/relay.env" <<EOF
NB_LOG_LEVEL=info
NB_LISTEN_ADDRESS=${NB_LISTEN}
NB_EXPOSED_ADDRESS=${NB_EXPOSED}
NB_AUTH_SECRET=${NETBIRD_RELAY_AUTH_SECRET}
NB_ENABLE_STUN=true
NB_STUN_PORTS=${NETBIRD_STUN_PORT}
${RELAY_ENV_EXTRA}
EOF

chmod 600 "${DATA_DIR}/relay.env" 2>/dev/null || true

cat > "${DATA_DIR}/openresty-relay-stream.conf" <<NGXEOF
# NetBird external relay — OpenResty stream TLS passthrough (ssl_preread)
# Place inside the http {} sibling stream {} block, or include from conf.d/stream.conf
# Domain: ${NETBIRD_RELAY_DOMAIN}  |  Backend: 127.0.0.1:${NETBIRD_RELAY_LOCAL_PORT}

upstream netbird_relay_tls_${NETBIRD_RELAY_DOMAIN//[^a-zA-Z0-9]/_} {
    server 127.0.0.1:${NETBIRD_RELAY_LOCAL_PORT};
}

server {
    listen 443;
    listen [::]:443;
    proxy_pass netbird_relay_tls_${NETBIRD_RELAY_DOMAIN//[^a-zA-Z0-9]/_};
    ssl_preread on;
    proxy_timeout 1d;
}
NGXEOF

cat > "${DATA_DIR}/main-server-config-snippet.yaml" <<SNIPEOF
# Paste into main NetBird server config.yaml (after enabling external relays)
# 粘贴到主 NetBird 的 config.yaml（启用外部 Relay 后）
#
# 1. Remove or comment: server.authSecret and server.stunPorts
# 2. Add the stuns/relays blocks below (add more entries per relay node)
# 3. Restart netbird-server container

  stuns:
    - uri: "stun:${NETBIRD_RELAY_DOMAIN}:${NETBIRD_STUN_PORT}"
      proto: "udp"

  relays:
    addresses:
      - "${NB_EXPOSED}"
    secret: "${NETBIRD_RELAY_AUTH_SECRET}"
    credentialsTTL: "24h"
SNIPEOF

log "Wrote ${DATA_DIR}/relay.env"
log "Wrote ${BASE_DIR}/docker-compose.override.yml (TLS mode: ${NETBIRD_RELAY_TLS_MODE})"
log "Exposed relay: ${NB_EXPOSED}"
log "STUN UDP port: ${NETBIRD_STUN_PORT}"
if [[ "${NETBIRD_RELAY_TLS_MODE}" != "letsencrypt_builtin" ]]; then
    log "OpenResty stream snippet: ${DATA_DIR}/openresty-relay-stream.conf"
    log "Install stream config on this host, then: openresty -t && openresty -s reload"
fi
log "Main server YAML snippet: ${DATA_DIR}/main-server-config-snippet.yaml"

exit 0
