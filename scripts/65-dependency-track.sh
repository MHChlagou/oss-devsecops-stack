#!/usr/bin/env bash
# Dependency-Track: stores every build's SBOM and re-evaluates it when new CVEs are published.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_root
load_env
ensure_network
ensure_dir "$DATA_ROOT/dtrack/db"
ensure_dir "$DATA_ROOT/dtrack/data" 1000:1000
compose_up dependency-track
wait_for_service dtrack-api /api/version 600
log "Dependency-Track: https://dtrack.${DOMAIN} (admin / admin, forced change at first login)"
log "next: create an automation team with BOM_UPLOAD + PROJECT_CREATION_UPLOAD, store its API key in Jenkins as 'dtrack-api-key'"
