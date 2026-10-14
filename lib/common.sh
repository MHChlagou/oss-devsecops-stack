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
  log "starting stack $stack"
  docker compose --project-name "$stack" --env-file "$ENV_FILE" --env-file "$VERSIONS_FILE" \
    -f "$file" up -d --remove-orphans "$@"
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

# wait_for_service <subdomain> [path] [timeout]. Goes through Traefik on localhost so it
# works before the wildcard DNS record exists.
wait_for_service() {
  local name="$1" path="${2:-/}" timeout="${3:-300}" elapsed=0 host="$1.${DOMAIN}"
  log "waiting for https://$host$path"
  until curl -ksS -o /dev/null -w '%{http_code}' --max-time 5 \
        --resolve "$host:443:127.0.0.1" "https://$host$path" | grep -qE '^[1-4][0-9]{2}$'; do
    sleep 5
    elapsed=$((elapsed + 5))
    [[ $elapsed -lt $timeout ]] || { warn "$host not answering after ${timeout}s, check: docker compose -p $name logs"; return 0; }
  done
  log "https://$host is up"
}
