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

# compose_files <stack-name>: prints the -f arguments for the stack, one per line.
compose_files() {
  local stack="$1" file="$STACKS_DIR/$1/docker-compose.yml"
  [[ -f "$file" ]] || die "no compose file for stack $stack"
  printf -- '-f\n%s\n' "$file"
  if [[ "$INGRESS" == ports && -f "$STACKS_DIR/$stack/docker-compose.ports.yml" ]]; then
    printf -- '-f\n%s\n' "$STACKS_DIR/$stack/docker-compose.ports.yml"
  fi
}

# compose_up <stack-name> [extra compose args]
compose_up() {
  local stack="$1"; shift || true
  local files
  mapfile -t files < <(compose_files "$stack")
  log "starting stack $stack (ingress: $INGRESS)"
  docker compose --project-name "$stack" --env-file "$ENV_FILE" --env-file "$VERSIONS_FILE" \
    "${files[@]}" up -d --remove-orphans "$@"
}

# sync_db_password <project> <db-service> <role> <password>. Postgres reads POSTGRES_PASSWORD
# only when it initialises an empty data directory, so a .env regenerated after the first
# start leaves the role with the old password and the application locked out. Re-align the
# role on every run: .env is the source of truth. The SQL goes through stdin, never argv.
sync_db_password() {
  local project="$1" service="$2" role="$3" password="$4" container
  container="$(docker ps -q --filter "label=com.docker.compose.project=$project" \
                                 --filter "label=com.docker.compose.service=$service")"
  [[ -n "$container" ]] || die "sync_db_password: no running container for $project/$service"
  password="${password//\'/\'\'}"
  printf 'ALTER ROLE "%s" PASSWORD '"'"'%s'"'"';\n' "$role" "$password" \
    | docker exec -i "$container" psql -q -v ON_ERROR_STOP=1 -U "$role" -d "$role" >/dev/null
}

# compose_down <stack-name>: stops and removes the containers and networks, keeps the data.
compose_down() {
  local stack="$1" files
  mapfile -t files < <(compose_files "$stack")
  log "stopping stack $stack"
  docker compose --project-name "$stack" --env-file "$ENV_FILE" --env-file "$VERSIONS_FILE" \
    "${files[@]}" down --remove-orphans
}

# Stacks in reverse install order, for uninstall and purge.
stacks_in_reverse_order() {
  local scripts=("$ROOT_DIR"/scripts/[0-9][0-9]-*.sh) i name
  for (( i = ${#scripts[@]} - 1; i >= 0; i-- )); do
    name="$(basename "${scripts[i]}" .sh)"; name="${name#*-}"
    [[ -d "$STACKS_DIR/$name" ]] && printf '%s\n' "$name"
  done
  return 0
}

# Removes what the installer created outside the stacks: data, network, images, certificate
# trust and the scanner wrappers. .env is kept on purpose: with the data gone it is harmless,
# and keeping it avoids the new-secrets-next-to-old-data trap.
purge_host_state() {
  local wrapper
  [[ -n "$DATA_ROOT" && "$DATA_ROOT" != / ]] || die "refusing to purge DATA_ROOT='$DATA_ROOT'"
  log "deleting $DATA_ROOT"
  rm -rf "${DATA_ROOT:?}"
  rm -rf "/etc/docker/certs.d/${REGISTRY_HOST}"
  for wrapper in /usr/local/bin/{trivy,gitleaks,semgrep,syft,hadolint,checkov,kics,zap}; do
    [[ -f "$wrapper" ]] && grep -q "Generated by oss-devsecops-stack" "$wrapper" && rm -f "$wrapper"
  done
  docker volume rm devsecops-trivy-cache >/dev/null 2>&1 || true
  docker image rm devsecops/jenkins:local devsecops/jenkins-agent:local >/dev/null 2>&1 || true
  docker network rm "$DOCKER_NETWORK" >/dev/null 2>&1 || true
  log "purged; .env was kept, delete it too for a completely fresh start"
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

# wait_for_service <name> <host-port> [path] [timeout] [extra-codes]. Polls the published port
# on localhost: Traefik's TLS entry point for that tool, or the container's own port in ports
# mode. Up means 2xx, 3xx, 401 or 403, plus any extra regex given (Vault answers 501/503
# while sealed). 404 is not up: behind Traefik it is the proxy answering for a backend that
# has not registered yet. Connection errors are expected while the tool starts and are not
# printed. A container stuck restarting, or the timeout, ends the wait with the stack's logs
# and a non-zero status so install.sh reports the component as failed.
wait_for_service() {
  local name="$1" port="$2" path="${3:-/}" timeout="${4:-300}" extra="${5:-}" elapsed=0 url restarting
  local scheme=https up_codes='^([23][0-9]{2}|401|403)$'
  [[ -n "$extra" ]] && up_codes="^([23][0-9]{2}|401|403|${extra})$"
  [[ "$INGRESS" == ports ]] && scheme=http
  url="${scheme}://127.0.0.1:${port}${path}"
  log "waiting for $name at $url (up to ${timeout}s)"
  until curl -ks -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null | grep -qE "$up_codes"; do
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
