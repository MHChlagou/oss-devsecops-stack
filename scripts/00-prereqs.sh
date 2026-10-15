#!/usr/bin/env bash
# Host preparation: Docker Engine, kernel settings, .env with generated secrets, data root, network.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_root

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "docker $(docker --version | awk '{print $3}') and compose plugin already present"
    return
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  case "$ID" in
    debian|ubuntu) ;;
    *) die "automatic Docker install covers Debian and Ubuntu only. Install Docker Engine and the compose plugin, then rerun." ;;
  esac
  log "installing Docker Engine from download.docker.com"
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
    "$(dpkg --print-architecture)" "$ID" "$VERSION_CODENAME" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

tune_kernel() {
  # SonarQube (Elasticsearch) refuses to start below these values.
  cat > /etc/sysctl.d/99-devsecops.conf <<'SYSCTL'
vm.max_map_count=524288
fs.file-max=131072
SYSCTL
  sysctl -q --system >/dev/null
}

# Variables exported before the first run (sudo HOST_ADDRESS=10.0.0.20 DATA_ROOT=/data ./install.sh)
# are written into the new .env, so the file never needs editing by hand. Only keys that exist in
# .env.example are taken, and only when .env is created: afterwards .env is the source of truth.
seed_env_from_environment() {
  local key value
  mapfile -t keys < <(grep -oE '^[A-Z_]+=' "$ENV_FILE" | tr -d '=')
  for key in "${keys[@]}"; do
    value="${!key:-}"
    [[ -n "$value" ]] || continue
    # .env is sourced by bash and read by compose: quote anything beyond plain characters.
    [[ "$value" != *\'* && "$value" != *$'\n'* ]] || die "$key: value must not contain a single quote or a newline"
    [[ "$value" =~ ^[A-Za-z0-9_./:@-]+$ ]] || value="'${value}'"
    value="${value//\\/\\\\}"; value="${value//&/\\&}"; value="${value//|/\\|}"
    sed -i "s|^${key}=.*$|${key}=${value}|" "$ENV_FILE"
    log "set $key from the environment"
  done
}

create_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ROOT_DIR/.env.example" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    seed_env_from_environment
    log "created .env from .env.example; HOST_ADDRESS and DATA_ROOT can be changed there"
  fi
  chmod 600 "$ENV_FILE"
  # Collect the empty secret keys first, then edit: never read and rewrite .env in one pass.
  local key
  mapfile -t empty_keys < <(grep -oE '^[A-Z_]+(_PASSWORD|_SECRET_KEY|_AES_KEY)=$' "$ENV_FILE" | tr -d '=')
  for key in "${empty_keys[@]}"; do
    sed -i "s|^${key}=$|${key}=$(random_secret)|" "$ENV_FILE"
    log "generated $key"
  done
}

check_resources() {
  # Budgets from docs/sizing.md, in MB and sustained vCPU, summed over the selected components
  # (INSTALL_COMPONENTS from install.sh, every component when run standalone) plus 4GB and
  # 2 vCPU per parallel build. Peaks do not coincide, so the host passes at 90% of the sum.
  local -A ram_mb=([traefik]=128 [keycloak]=1536 [vault]=256 [gitea]=1536 [jenkins]=2560
                   [sonarqube]=5120 [nexus]=4608 [defectdojo]=3072 [dependency-track]=5632
                   [observability]=2560 [scanners]=0)
  local -A cpu=([traefik]=0 [keycloak]=0 [vault]=0 [gitea]=0 [jenkins]=1 [sonarqube]=1
                [nexus]=1 [defectdojo]=1 [dependency-track]=1 [observability]=1 [scanners]=0)
  local components="${INSTALL_COMPONENTS:-${!ram_mb[*]}}"
  local agents="${JENKINS_MAX_AGENTS:-5}"
  local need_mb=3072 need_cpu=1 c mem_gb cpus need_gb
  for c in ${components//,/ }; do
    need_mb=$(( need_mb + ${ram_mb[$c]:-0} ))
    need_cpu=$(( need_cpu + ${cpu[$c]:-0} ))
  done
  need_mb=$(( need_mb + 4096 * agents ))
  need_cpu=$(( need_cpu + 2 * agents ))
  need_gb=$(( (need_mb + 1023) / 1024 ))
  mem_gb=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 ))
  cpus=$(nproc)
  log "host has ${mem_gb}GB RAM and ${cpus} CPUs; selected components with ${agents} parallel builds need about ${need_gb}GB and ${need_cpu} vCPU"
  [[ $(( mem_gb * 10 )) -ge $(( need_gb * 9 )) ]] || warn "RAM below the budget for this selection with JENKINS_MAX_AGENTS=${agents}. Lower the agent count in .env, split onto two hosts, or add memory (docs/sizing.md, docs/minimal-setup.md)."
  [[ $(( cpus * 10 )) -ge $(( need_cpu * 9 )) ]] || warn "CPU below the budget for this selection. Builds queue on CPU rather than fail."
}

install_docker
tune_kernel
create_env
load_env
check_resources
ensure_dir "$DATA_ROOT"
chmod 750 "$DATA_ROOT"
ensure_network
log "prerequisites done"
