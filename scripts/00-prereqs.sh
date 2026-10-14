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

create_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ROOT_DIR/.env.example" "$ENV_FILE"
    log "created .env from .env.example, edit DOMAIN and DATA_ROOT if needed"
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
  # Budget from docs/sizing.md: 24GB and 6 vCPU for the platform, plus 4GB and 2 vCPU per concurrent build.
  local mem_gb cpus agents need_gb need_cpu
  agents="${JENKINS_MAX_AGENTS:-5}"
  need_gb=$(( 24 + 4 * agents ))
  need_cpu=$(( 6 + 2 * agents ))
  mem_gb=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 ))
  cpus=$(nproc)
  log "host has ${mem_gb}GB RAM and ${cpus} CPUs; ${agents} parallel builds need about ${need_gb}GB and ${need_cpu} vCPU"
  [[ $mem_gb -ge $need_gb ]] || warn "RAM below the budget for JENKINS_MAX_AGENTS=${agents}. Lower it in .env, split onto two hosts, or add memory (docs/sizing.md)."
  [[ $cpus -ge $need_cpu ]] || warn "CPU below the budget for JENKINS_MAX_AGENTS=${agents}. Builds will queue on CPU rather than fail."
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
