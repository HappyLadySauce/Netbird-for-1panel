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
        letsencrypt_builtin|custom_cert) ;;
        openresty_cert)
            fail "openresty_cert is removed; use custom_cert and set certificate file paths on the install form"
            ;;
        *) fail "NETBIRD_RELAY_TLS_MODE must be custom_cert or letsencrypt_builtin" ;;
    esac
}

validate_auth_secret() {
    local s="${1:-}"
    [[ -n "${s}" ]] || fail "NETBIRD_RELAY_AUTH_SECRET is required"
    local len=${#s}
    (( len >= 16 && len <= 256 )) || fail "NETBIRD_RELAY_AUTH_SECRET length must be 16-256 characters"
    if [[ ! "${s}" =~ ^[A-Za-z0-9+/=_-]+$ ]]; then
        fail "NETBIRD_RELAY_AUTH_SECRET contains invalid characters (allowed: A-Za-z0-9 + / = _ -)"
    fi
}

relay_load_env "${BASE_DIR}" || true

NETBIRD_RELAY_DOMAIN="${NETBIRD_RELAY_DOMAIN:-}"
NETBIRD_RELAY_AUTH_SECRET="${NETBIRD_RELAY_AUTH_SECRET:-}"
NETBIRD_RELAY_TLS_MODE="${NETBIRD_RELAY_TLS_MODE:-custom_cert}"
NETBIRD_RELAY_LOCAL_PORT="${NETBIRD_RELAY_LOCAL_PORT:-33080}"
NETBIRD_RELAY_PUBLIC_PORT="${NETBIRD_RELAY_PUBLIC_PORT:-443}"
NETBIRD_STUN_PORT="${NETBIRD_STUN_PORT:-3478}"
NETBIRD_LETSENCRYPT_EMAIL="${NETBIRD_LETSENCRYPT_EMAIL:-}"
NETBIRD_TLS_CERT_FILE="${NETBIRD_TLS_CERT_FILE:-}"
NETBIRD_TLS_KEY_FILE="${NETBIRD_TLS_KEY_FILE:-}"

[[ -n "${NETBIRD_RELAY_DOMAIN}" ]] || fail "NETBIRD_RELAY_DOMAIN is required"

validate_domain "${NETBIRD_RELAY_DOMAIN}"
validate_tls_mode "${NETBIRD_RELAY_TLS_MODE}"
validate_auth_secret "${NETBIRD_RELAY_AUTH_SECRET}"
validate_port "NETBIRD_RELAY_LOCAL_PORT" "${NETBIRD_RELAY_LOCAL_PORT}"
validate_port "NETBIRD_RELAY_PUBLIC_PORT" "${NETBIRD_RELAY_PUBLIC_PORT}"
validate_port "NETBIRD_STUN_PORT" "${NETBIRD_STUN_PORT}"

log "Cleaning up containers from any previous failed install ..."
relay_cleanup_stale_containers
relay_assert_ports_free

mkdir -p "${DATA_DIR}/relay-data"

NB_EXPOSED="rels://${NETBIRD_RELAY_DOMAIN}:${NETBIRD_RELAY_PUBLIC_PORT}"
RELAY_ENV_EXTRA=""
COMPOSE_PORTS=""
COMPOSE_VOLUMES="      - ./data/relay-data:/data"

case "${NETBIRD_RELAY_TLS_MODE}" in
    letsencrypt_builtin)
        [[ -n "${NETBIRD_LETSENCRYPT_EMAIL}" ]] || fail "NETBIRD_LETSENCRYPT_EMAIL is required for letsencrypt_builtin"
        NB_LISTEN=":443"
        COMPOSE_PORTS=$(cat <<PEOF
      - "${NETBIRD_STUN_PORT}:${NETBIRD_STUN_PORT}/udp"
      - "80:80"
      - "443:443"
PEOF
)
        RELAY_ENV_EXTRA=$(cat <<LEOF

NB_LETSENCRYPT_DOMAINS=${NETBIRD_RELAY_DOMAIN}
NB_LETSENCRYPT_EMAIL=${NETBIRD_LETSENCRYPT_EMAIL}
NB_LETSENCRYPT_DATA_DIR=/data/letsencrypt
LEOF
)
        ;;
    custom_cert)
        [[ -n "${NETBIRD_TLS_CERT_FILE}" && -f "${NETBIRD_TLS_CERT_FILE}" ]] \
            || fail "NETBIRD_TLS_CERT_FILE must point to an existing certificate file on the host"
        [[ -n "${NETBIRD_TLS_KEY_FILE}" && -f "${NETBIRD_TLS_KEY_FILE}" ]] \
            || fail "NETBIRD_TLS_KEY_FILE must point to an existing private key file on the host"
        NB_LISTEN=":${NETBIRD_RELAY_LOCAL_PORT}"
        CERTS_DIR="${DATA_DIR}/certs"
        mkdir -p "${CERTS_DIR}"
        install -m 0644 "${NETBIRD_TLS_CERT_FILE}" "${CERTS_DIR}/fullchain.pem"
        install -m 0600 "${NETBIRD_TLS_KEY_FILE}" "${CERTS_DIR}/privkey.pem"
        COMPOSE_PORTS=$(cat <<PEOF
      - "${NETBIRD_STUN_PORT}:${NETBIRD_STUN_PORT}/udp"
      - "127.0.0.1:${NETBIRD_RELAY_LOCAL_PORT}:${NETBIRD_RELAY_LOCAL_PORT}"
PEOF
)
        COMPOSE_VOLUMES=$(cat <<VEOF
      - ./data/relay-data:/data
      - ./data/certs:/certs:ro
VEOF
)
        RELAY_ENV_EXTRA=$(cat <<CCEOF

NB_TLS_CERT_FILE=/certs/fullchain.pem
NB_TLS_KEY_FILE=/certs/privkey.pem
CCEOF
)
        log "Copied TLS material to ${CERTS_DIR}/ (fullchain.pem, privkey.pem)"
        ;;
esac

# 1Panel only loads docker-compose.yml (not docker-compose.override.yml).
cat > "${BASE_DIR}/docker-compose.yml" <<DCEOF
services:
  relay:
    image: netbirdio/relay:latest
    container_name: \${CONTAINER_NAME}
    restart: unless-stopped
    env_file:
      - ./data/relay.env
    ports:
${COMPOSE_PORTS}
    volumes:
${COMPOSE_VOLUMES}
    labels:
      createdBy: "Apps"
    logging:
      driver: json-file
      options:
        max-size: "500m"
        max-file: "2"
DCEOF
rm -f "${BASE_DIR}/docker-compose.override.yml"

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

if [[ "${NETBIRD_RELAY_TLS_MODE}" == "custom_cert" ]]; then
    cat > "${DATA_DIR}/openresty-relay-stream.conf" <<NGXEOF
# NetBird external relay — OpenResty stream TLS passthrough (optional when OpenResty holds :443)
# 当本机 443 由 1Panel OpenResty 占用时，在 stream {} 中 include 本文件
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
fi

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
log "Wrote ${BASE_DIR}/docker-compose.yml (TLS mode: ${NETBIRD_RELAY_TLS_MODE})"
log "Exposed relay: ${NB_EXPOSED}"
log "STUN UDP port: ${NETBIRD_STUN_PORT}"
if [[ "${NETBIRD_RELAY_TLS_MODE}" == "custom_cert" ]]; then
    log "TLS certs in ${DATA_DIR}/certs/ (from ${NETBIRD_TLS_CERT_FILE})"
    log "OpenResty stream (optional, if :443 is on OpenResty): ${DATA_DIR}/openresty-relay-stream.conf"
fi
log "Main server YAML snippet: ${DATA_DIR}/main-server-config-snippet.yaml"

exit 0
