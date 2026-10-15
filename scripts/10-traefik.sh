#!/usr/bin/env bash
# Traefik: TLS termination, one entry point per tool at https://${HOST_ADDRESS}:<port>, routes
# built from Docker labels. No DNS record is needed: the certificate is issued for HOST_ADDRESS.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_root
load_env
require_traefik_ingress
ensure_network

ensure_dir "$DATA_ROOT/traefik/certs"
ensure_dir "$DATA_ROOT/traefik/dynamic"

# Dashboard credentials: the password never appears on a command line.
printf '%s:%s\n' "$TRAEFIK_DASHBOARD_USER" \
  "$(openssl passwd -apr1 -stdin <<<"$TRAEFIK_DASHBOARD_PASSWORD")" > "$DATA_ROOT/traefik/usersfile"
chmod 600 "$DATA_ROOT/traefik/usersfile"

# Certificate for HOST_ADDRESS. The client's own certificate (internal CA) wins when present as
# server.crt / server.key; otherwise a self-signed one is generated once and reused.
CERT_DIR="$DATA_ROOT/traefik/certs"
if [[ -f "$CERT_DIR/server.crt" && -f "$CERT_DIR/server.key" ]]; then
  log "using existing certificate $CERT_DIR/server.crt"
else
  if [[ "$HOST_ADDRESS" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SAN="IP:${HOST_ADDRESS}"
  else
    SAN="DNS:${HOST_ADDRESS}"
  fi
  log "generating a self-signed certificate for ${HOST_ADDRESS} (10 years)"
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
    -subj "/CN=${HOST_ADDRESS}" -addext "subjectAltName=${SAN},DNS:localhost,IP:127.0.0.1" \
    -keyout "$CERT_DIR/server.key" -out "$CERT_DIR/server.crt" 2>/dev/null
  chmod 600 "$CERT_DIR/server.key"
fi
# Trust it for the host's Docker daemon so that pushes to the Nexus registry work as-is.
install -D -m 644 "$CERT_DIR/server.crt" "/etc/docker/certs.d/${REGISTRY_HOST}/ca.crt"

cat > "$DATA_ROOT/traefik/dynamic/tls.yml" <<DYNAMIC
tls:
  stores:
    default:
      defaultCertificate:
        certFile: /certs/server.crt
        keyFile: /certs/server.key
DYNAMIC

# Static config: one TLS entry point per tool, named after the router that uses it in the
# stack's compose labels. The ports are the same ones ports mode publishes directly.
entrypoint() { printf '  %s:\n    address: ":%s"\n' "$1" "$2"; }
{
  cat <<STATIC
api:
  dashboard: true
log:
  level: INFO
accessLog: {}
metrics:
  prometheus:
    entryPoint: metrics
entryPoints:
  metrics:
    address: ":8082"
STATIC
  entrypoint websecure "$TRAEFIK_DASHBOARD_PORT"
  entrypoint gitea "$GITEA_HTTP_PORT"
  entrypoint jenkins "$JENKINS_HTTP_PORT"
  entrypoint sonarqube "$SONARQUBE_HTTP_PORT"
  entrypoint nexus "$NEXUS_HTTP_PORT"
  entrypoint registry "$REGISTRY_PORT"
  entrypoint keycloak "$KEYCLOAK_HTTP_PORT"
  entrypoint vault "$VAULT_HTTP_PORT"
  entrypoint defectdojo "$DEFECTDOJO_HTTP_PORT"
  entrypoint dtrack "$DTRACK_HTTP_PORT"
  entrypoint dtrack-api "$DTRACK_API_PORT"
  entrypoint grafana "$GRAFANA_HTTP_PORT"
  entrypoint prometheus "$PROMETHEUS_HTTP_PORT"
  cat <<STATIC
providers:
  docker:
    exposedByDefault: false
    network: ${DOCKER_NETWORK}
  file:
    directory: /etc/traefik/dynamic
    watch: true
STATIC
} > "$DATA_ROOT/traefik/traefik.yml"

compose_up traefik
wait_for_service traefik "$TRAEFIK_DASHBOARD_PORT" /dashboard/ 60
log "Traefik dashboard: ${TRAEFIK_URL}/dashboard/ (user ${TRAEFIK_DASHBOARD_USER}, password TRAEFIK_DASHBOARD_PASSWORD in .env)"
log "certificate: ${CERT_DIR}/server.crt. Import it on developer machines, or replace server.crt/server.key with one from the client's CA and rerun."
