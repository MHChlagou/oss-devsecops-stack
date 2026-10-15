#!/usr/bin/env bash
# DefectDojo: single vulnerability inbox for SAST, SCA, container, IaC and DAST reports.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_root
load_env
require_traefik_ingress
ensure_network
ensure_dir "$DATA_ROOT/defectdojo/db"
ensure_dir "$DATA_ROOT/defectdojo/media" 1001:1001
compose_up defectdojo
wait_for_service defectdojo "$DEFECTDOJO_HTTP_PORT" /login 600
log "DefectDojo: ${DEFECTDOJO_URL} (user admin, password DEFECTDOJO_ADMIN_PASSWORD in .env)"
log "next: create a product per application and an API key for Jenkins (credential 'defectdojo-api-key')"
