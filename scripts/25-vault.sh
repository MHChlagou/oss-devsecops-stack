#!/usr/bin/env bash
# Vault: secrets store for pipelines and applications. Init and unseal are manual by design:
# the unseal keys must never be written to disk by an installer.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_root
load_env
ensure_network

ensure_dir "$DATA_ROOT/vault/config"
ensure_dir "$DATA_ROOT/vault/file" 100:1000
ensure_dir "$DATA_ROOT/vault/logs" 100:1000

cat > "$DATA_ROOT/vault/config/vault.hcl" <<HCL
ui = true
disable_mlock = false
api_addr = "https://vault.${DOMAIN}"

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

storage "file" {
  path = "/vault/file"
}
HCL

compose_up vault
wait_for_service vault /v1/sys/health 120
cat <<MSG
Vault is running but sealed. Initialise it once, from a trusted terminal:
  docker exec -it vault vault operator init -key-shares=5 -key-threshold=3
Store the 5 unseal keys and the root token offline (password manager, split between people).
Unseal after every restart with 3 keys:
  docker exec -it vault vault operator unseal
MSG
