#!/usr/bin/env bash
# Prometheus + Grafana + Loki: metrics and logs for the platform itself (host, containers, Traefik).
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_root
load_env
require_traefik_ingress
ensure_network
ensure_dir "$DATA_ROOT/observability/prometheus" 65534:65534
ensure_dir "$DATA_ROOT/observability/grafana" 472:472
ensure_dir "$DATA_ROOT/observability/loki" 10001:10001
compose_up observability
wait_for_service grafana "$GRAFANA_HTTP_PORT" /api/health 180
log "Grafana: ${GRAFANA_URL} (user admin, password GRAFANA_ADMIN_PASSWORD in .env)"
log "Prometheus and Loki are already provisioned as datasources. Import dashboards 1860 (node) and 14282 (cadvisor)."
