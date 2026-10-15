#!/usr/bin/env bash
# SonarQube Community Build: code quality and quality gates for PHP and TypeScript.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_root
load_env
ensure_network
[[ "$(sysctl -n vm.max_map_count)" -ge 262144 ]] || die "vm.max_map_count too low, run scripts/00-prereqs.sh"
ensure_dir "$DATA_ROOT/sonarqube/db"
ensure_dir "$DATA_ROOT/sonarqube/data" 1000:1000
ensure_dir "$DATA_ROOT/sonarqube/extensions" 1000:1000
ensure_dir "$DATA_ROOT/sonarqube/logs" 1000:1000
compose_up sonarqube
sync_db_password sonarqube sonarqube-db sonar "$SONAR_DB_PASSWORD"
wait_for_service sonarqube "$SONARQUBE_HTTP_PORT" /api/system/status 600
log "SonarQube: ${SONARQUBE_URL} (admin / admin, forced change at first login)"
log "next: generate a token for Jenkins and add it as credential 'sonarqube-token'"
