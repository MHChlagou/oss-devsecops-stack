#!/usr/bin/env bash
# Nexus Repository Community Edition: npm, composer and Docker image hosting plus proxy caches.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_root
load_env
ensure_network
ensure_dir "$DATA_ROOT/nexus/data" 200:200
compose_up nexus
wait_for_service nexus /service/rest/v1/status 600
log "Nexus: https://nexus.${DOMAIN}"
log "first admin password: sudo cat ${DATA_ROOT}/nexus/data/admin.password (deleted after the first login)"
log "next: create repositories npm-proxy, composer-proxy, docker-hosted (HTTP connector port 5000 -> https://registry.${DOMAIN})"
