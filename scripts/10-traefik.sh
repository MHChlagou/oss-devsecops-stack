#!/usr/bin/env bash
# Traefik: single TLS entry point, routes <name>.${DOMAIN} to each stack by Docker labels.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_root
load_env
require_traefik_ingress
ensure_network

ensure_dir "$DATA_ROOT/traefik/letsencrypt"
touch "$DATA_ROOT/traefik/letsencrypt/acme.json"
chmod 600 "$DATA_ROOT/traefik/letsencrypt/acme.json"

# Dashboard credentials: the password never appears on a command line.
printf '%s:%s\n' "$TRAEFIK_DASHBOARD_USER" \
  "$(openssl passwd -apr1 -stdin <<<"$TRAEFIK_DASHBOARD_PASSWORD")" > "$DATA_ROOT/traefik/usersfile"
chmod 600 "$DATA_ROOT/traefik/usersfile"

# Static config. The ACME resolver is only declared when CERT_RESOLVER=le, otherwise Traefik
# serves its built-in self-signed certificate (fine for a private network behind a corporate CA later).
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
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"
  metrics:
    address: ":8082"
providers:
  docker:
    exposedByDefault: false
    network: ${DOCKER_NETWORK}
STATIC
  if [[ "${CERT_RESOLVER:-}" == "le" ]]; then
    [[ -n "${ACME_EMAIL:-}" ]] || die "CERT_RESOLVER=le needs ACME_EMAIL in .env"
    cat <<STATIC
certificatesResolvers:
  le:
    acme:
      email: ${ACME_EMAIL}
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
STATIC
  fi
} > "$DATA_ROOT/traefik/traefik.yml"

compose_up traefik
wait_for_service traefik /dashboard/ 60
