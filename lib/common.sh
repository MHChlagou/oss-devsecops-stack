#!/usr/bin/env bash
# Shared helpers for install.sh and scripts/*.sh. Source, do not execute.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACKS_DIR="$ROOT_DIR/stacks"
ENV_FILE="$ROOT_DIR/.env"
VERSIONS_FILE="$ROOT_DIR/versions.env"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARN %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '[%s] ERROR %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "run as root (sudo $0)"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

# Loads .env and versions.env into the environment. Values are exported so that
# docker compose and envsubst-style templating see them.
load_env() {
  [[ -f "$ENV_FILE" ]] || die ".env not found, run scripts/00-prereqs.sh first"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  # shellcheck disable=SC1090
  source "$VERSIONS_FILE"
  set +a
  : "${DATA_ROOT:?DATA_ROOT must be set in .env}"
  : "${DOCKER_NETWORK:?DOCKER_NETWORK must be set in .env}"
  derive_urls
}

# Public URLs. Every tool is reached on HOST_ADDRESS (server name or IP, no DNS zone needed)
# at its own port: https through Traefik, plain http in ports mode. Explicit *_URL values in
# .env win (external proxy case).
derive_urls() {
  INGRESS="${INGRESS:-traefik}"
  local scheme
  case "$INGRESS" in
    traefik) scheme=https ;;
    ports) scheme=http ;;
    *) die "INGRESS must be traefik or ports, got '$INGRESS'" ;;
  esac
  : "${HOST_ADDRESS:=$(hostname -I 2>/dev/null | awk '{print $1}')}"
  [[ -n "$HOST_ADDRESS" ]] || die "HOST_ADDRESS must be set in .env (server name or IP)"
  : "${GITEA_HTTP_PORT:=3000}"
  : "${JENKINS_HTTP_PORT:=8080}"
  : "${SONARQUBE_HTTP_PORT:=9000}"
  : "${NEXUS_HTTP_PORT:=8081}"
  : "${REGISTRY_PORT:=5000}"
  : "${KEYCLOAK_HTTP_PORT:=8180}"
  : "${VAULT_HTTP_PORT:=8200}"
  : "${DEFECTDOJO_HTTP_PORT:=8083}"
  : "${DTRACK_HTTP_PORT:=8090}"
  : "${DTRACK_API_PORT:=8091}"
  : "${GRAFANA_HTTP_PORT:=3001}"
  : "${PROMETHEUS_HTTP_PORT:=9090}"
  : "${TRAEFIK_DASHBOARD_PORT:=443}"
  : "${GITEA_URL:=${scheme}://${HOST_ADDRESS}:${GITEA_HTTP_PORT}}"
  : "${JENKINS_URL:=${scheme}://${HOST_ADDRESS}:${JENKINS_HTTP_PORT}}"
  : "${SONARQUBE_URL:=${scheme}://${HOST_ADDRESS}:${SONARQUBE_HTTP_PORT}}"
  : "${NEXUS_URL:=${scheme}://${HOST_ADDRESS}:${NEXUS_HTTP_PORT}}"
  : "${REGISTRY_HOST:=${HOST_ADDRESS}:${REGISTRY_PORT}}"
  : "${KEYCLOAK_URL:=https://${HOST_ADDRESS}:${KEYCLOAK_HTTP_PORT}}"
  : "${VAULT_URL:=https://${HOST_ADDRESS}:${VAULT_HTTP_PORT}}"
  : "${DEFECTDOJO_URL:=https://${HOST_ADDRESS}:${DEFECTDOJO_HTTP_PORT}}"
  : "${DTRACK_URL:=https://${HOST_ADDRESS}:${DTRACK_HTTP_PORT}}"
  : "${DTRACK_API_URL:=https://${HOST_ADDRESS}:${DTRACK_API_PORT}}"
  : "${GRAFANA_URL:=https://${HOST_ADDRESS}:${GRAFANA_HTTP_PORT}}"
  : "${PROMETHEUS_URL:=https://${HOST_ADDRESS}:${PROMETHEUS_HTTP_PORT}}"
  : "${TRAEFIK_URL:=https://${HOST_ADDRESS}:${TRAEFIK_DASHBOARD_PORT}}"
  # Gitea matches webhook targets by host, not port, so this is the platform host and nothing else.
  : "${GITEA_WEBHOOK_ALLOWED_HOSTS:=${HOST_ADDRESS}}"
  : "${ADMIN_EMAIL:=devsecops@localhost}"
  GITEA_HOST="${GITEA_URL#*://}"; GITEA_HOST="${GITEA_HOST%%/*}"; GITEA_HOST="${GITEA_HOST%%:*}"
  export INGRESS HOST_ADDRESS ADMIN_EMAIL \
         GITEA_HTTP_PORT JENKINS_HTTP_PORT SONARQUBE_HTTP_PORT NEXUS_HTTP_PORT REGISTRY_PORT \
         KEYCLOAK_HTTP_PORT VAULT_HTTP_PORT DEFECTDOJO_HTTP_PORT DTRACK_HTTP_PORT DTRACK_API_PORT \
         GRAFANA_HTTP_PORT PROMETHEUS_HTTP_PORT TRAEFIK_DASHBOARD_PORT \
         GITEA_URL JENKINS_URL SONARQUBE_URL NEXUS_URL REGISTRY_HOST KEYCLOAK_URL VAULT_URL \
         DEFECTDOJO_URL DTRACK_URL DTRACK_API_URL GRAFANA_URL PROMETHEUS_URL TRAEFIK_URL \
         GITEA_WEBHOOK_ALLOWED_HOSTS GITEA_HOST
}

# Components that only work behind Traefik call this first.
require_traefik_ingress() {
  [[ "$INGRESS" == traefik ]] || die "this component needs INGRESS=traefik; only gitea, jenkins, sonarqube and nexus support ports mode"
}

random_secret() {
  # 32 url-safe characters, no shell-special characters.
  openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32
}

ensure_network() {
  if ! docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then
    log "creating docker network $DOCKER_NETWORK"
    docker network create "$DOCKER_NETWORK" >/dev/null
  fi
}

# Creates a data directory owned by the given uid:gid (containers often run unprivileged).
ensure_dir() {
  local dir="$1" owner="${2:-}"
  mkdir -p "$dir"
  [[ -n "$owner" ]] && chown -R "$owner" "$dir"
  return 0
}

# compose_up <stack-name> [extra compose args]
compose_up() {
  local stack="$1"; shift || true
  local file="$STACKS_DIR/$stack/docker-compose.yml"
  [[ -f "$file" ]] || die "no compose file for stack $stack"
  local files=(-f "$file")
  if [[ "$INGRESS" == ports && -f "$STACKS_DIR/$stack/docker-compose.ports.yml" ]]; then
    files+=(-f "$STACKS_DIR/$stack/docker-compose.ports.yml")
  fi
  log "starting stack $stack (ingress: $INGRESS)"
  docker compose --project-name "$stack" --env-file "$ENV_FILE" --env-file "$VERSIONS_FILE" \
    "${files[@]}" up -d --remove-orphans "$@"
}

compose_down() {
  local stack="$1"
  docker compose --project-name "$stack" --env-file "$ENV_FILE" --env-file "$VERSIONS_FILE" \
    -f "$STACKS_DIR/$stack/docker-compose.yml" down
}

# wait_for_url <url> [timeout-seconds]. Accepts any HTTP answer, including 401/403.
wait_for_url() {
  local url="$1" timeout="${2:-300}" elapsed=0
  log "waiting for $url"
  until curl -ksS -o /dev/null -w '%{http_code}' --max-time 5 "$url" | grep -qE '^[1-4][0-9]{2}$'; do
    sleep 5
    elapsed=$((elapsed + 5))
    [[ $elapsed -lt $timeout ]] || { warn "$url not answering after ${timeout}s, continuing"; return 0; }
  done
  log "$url is up"
}

# Resolves the version-tag key for a scanner wrapper, used by scripts/80-scanners.sh.
image_for() {
  local var="$1"
  printf '%s' "${!var:?$var not set in versions.env}"
}

# crash_looping <compose-project>: prints the containers of the project that are in the
# restarting state or have already been restarted twice. A fast loop shows as "Up 3 seconds"
# most of the time, so the status alone is not enough.
crash_looping() {
  local ids
  ids="$(docker ps -aq --filter "label=com.docker.compose.project=$1")"
  [[ -n "$ids" ]] || return 0
  # shellcheck disable=SC2086
  docker inspect -f '{{.Name}} {{.State.Status}} {{.RestartCount}}' $ids \
    | awk '$2 == "restarting" || $3 >= 2 { sub("^/", "", $1); printf "%s ", $1 }'
}

# wait_for_service <name> <host-port> [path] [timeout]. Polls the published port on
# localhost: Traefik's TLS entry point for that tool, or the container's own port in ports mode.
# Connection errors are expected while the tool starts (first start includes database setup),
# so they are not printed. A container stuck restarting, or the timeout, ends the wait with the
# stack's logs and a non-zero status so install.sh reports the component as failed.
wait_for_service() {
  local name="$1" port="$2" path="${3:-/}" timeout="${4:-300}" elapsed=0 url restarting
  local scheme=https
  [[ "$INGRESS" == ports ]] && scheme=http
  url="${scheme}://127.0.0.1:${port}${path}"
  log "waiting for $name at $url (up to ${timeout}s)"
  until curl -ks -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null | grep -qE '^[1-4][0-9]{2}$'; do
    sleep 5
    elapsed=$((elapsed + 5))
    restarting="$(crash_looping "$name")"
    if [[ -n "$restarting" ]]; then
      warn "$name: container keeps restarting: ${restarting}last log lines follow"
      docker compose --project-name "$name" logs --tail 40 >&2 || true
      return 1
    fi
    if [[ $elapsed -ge $timeout ]]; then
      warn "$name not answering after ${timeout}s, last log lines follow"
      docker compose --project-name "$name" logs --tail 40 >&2 || true
      return 1
    fi
    (( elapsed % 30 )) || log "still waiting for $name (${elapsed}s)"
  done
  log "$name is up"
}
