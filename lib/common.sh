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
  : "${DOMAIN:?DOMAIN must be set in .env}"
  : "${DATA_ROOT:?DATA_ROOT must be set in .env}"
  : "${DOCKER_NETWORK:?DOCKER_NETWORK must be set in .env}"
  derive_urls
}

# Public URLs per ingress mode. Explicit *_URL values in .env win (external proxy case).
derive_urls() {
  INGRESS="${INGRESS:-traefik}"
  case "$INGRESS" in
    traefik)
      : "${GITEA_URL:=https://gitea.${DOMAIN}}"
      : "${JENKINS_URL:=https://jenkins.${DOMAIN}}"
      : "${SONARQUBE_URL:=https://sonarqube.${DOMAIN}}"
      : "${NEXUS_URL:=https://nexus.${DOMAIN}}"
      : "${REGISTRY_HOST:=registry.${DOMAIN}}"
      : "${GITEA_WEBHOOK_ALLOWED_HOSTS:=*.${DOMAIN}}"
      ;;
    ports)
      : "${HOST_ADDRESS:=$(hostname -I 2>/dev/null | awk '{print $1}')}"
      [[ -n "$HOST_ADDRESS" ]] || die "HOST_ADDRESS must be set in .env for INGRESS=ports"
      : "${GITEA_URL:=http://${HOST_ADDRESS}:${GITEA_HTTP_PORT:-3000}}"
      : "${JENKINS_URL:=http://${HOST_ADDRESS}:${JENKINS_HTTP_PORT:-8080}}"
      : "${SONARQUBE_URL:=http://${HOST_ADDRESS}:${SONARQUBE_HTTP_PORT:-9000}}"
      : "${NEXUS_URL:=http://${HOST_ADDRESS}:${NEXUS_HTTP_PORT:-8081}}"
      : "${REGISTRY_HOST:=${HOST_ADDRESS}:${REGISTRY_PORT:-5000}}"
      : "${GITEA_WEBHOOK_ALLOWED_HOSTS:=${HOST_ADDRESS}}"
      ;;
    *) die "INGRESS must be traefik or ports, got '$INGRESS'" ;;
  esac
  GITEA_HOST="${GITEA_URL#*://}"; GITEA_HOST="${GITEA_HOST%%/*}"; GITEA_HOST="${GITEA_HOST%%:*}"
  export INGRESS HOST_ADDRESS GITEA_URL JENKINS_URL SONARQUBE_URL NEXUS_URL REGISTRY_HOST \
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

# wait_for_service <name> [path] [timeout] [host-port]. Behind Traefik it goes through
# localhost:443 with --resolve so it works before the wildcard DNS record exists; in ports
# mode it hits the published host port directly.
wait_for_service() {
  local name="$1" path="${2:-/}" timeout="${3:-300}" port="${4:-}" elapsed=0 url
  local curl_opts=(-ksS -o /dev/null -w '%{http_code}' --max-time 5)
  if [[ "$INGRESS" == ports ]]; then
    [[ -n "$port" ]] || die "wait_for_service $name: host port required in ports mode"
    url="http://127.0.0.1:${port}${path}"
  else
    url="https://${name}.${DOMAIN}${path}"
    curl_opts+=(--resolve "${name}.${DOMAIN}:443:127.0.0.1")
  fi
  log "waiting for $url"
  until curl "${curl_opts[@]}" "$url" | grep -qE '^[1-4][0-9]{2}$'; do
    sleep 5
    elapsed=$((elapsed + 5))
    [[ $elapsed -lt $timeout ]] || { warn "$url not answering after ${timeout}s, check: docker compose -p $name logs"; return 0; }
  done
  log "$url is up"
}
