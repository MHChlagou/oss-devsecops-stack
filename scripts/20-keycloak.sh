#!/usr/bin/env bash
# Keycloak: OpenID Connect provider for single sign-on across every tool.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_root
load_env
require_traefik_ingress
ensure_network
ensure_dir "$DATA_ROOT/keycloak/db"
compose_up keycloak
sync_db_password keycloak keycloak-db keycloak "$KEYCLOAK_DB_PASSWORD"
wait_for_service keycloak "$KEYCLOAK_HTTP_PORT" / 300
log "Keycloak admin console: ${KEYCLOAK_URL}/admin (user admin, password KEYCLOAK_ADMIN_PASSWORD in .env)"
log "next: create a realm 'devsecops' and one OIDC client per tool (gitea, jenkins, sonarqube, nexus, defectdojo, dtrack, grafana)"
