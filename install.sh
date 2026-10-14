#!/usr/bin/env bash
# DevSecOps platform installer. Runs every scripts/NN-<component>.sh in order.
#
#   sudo ./install.sh                  install everything
#   sudo ./install.sh --list           show components in run order
#   sudo ./install.sh --only gitea,jenkins
#   sudo ./install.sh --skip gitea
#   sudo ./install.sh --uninstall sonarqube   stop one stack (data is kept)

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib/common.sh
source lib/common.sh

usage() { sed -n '2,9p' "$0"; exit "${1:-0}"; }

component_of() { local f; f="$(basename "$1" .sh)"; printf '%s' "${f#*-}"; }

list_components() {
  for s in scripts/[0-9][0-9]-*.sh; do printf '%s\n' "$(component_of "$s")"; done
}

in_list() { local needle="$1" list=",$2,"; [[ "$list" == *",$needle,"* ]]; }

ONLY="" SKIP="" UNINSTALL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) list_components; exit 0 ;;
    --only) ONLY="$2"; shift 2 ;;
    --skip) SKIP="$2"; shift 2 ;;
    --uninstall) UNINSTALL="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) warn "unknown argument $1"; usage 1 ;;
  esac
done

require_root
require_cmd curl
require_cmd openssl

if [[ -n "$UNINSTALL" ]]; then
  load_env
  compose_down "$UNINSTALL"
  exit 0
fi

# prereqs always runs first unless explicitly skipped: it creates .env and installs docker.
failed=()
for script in scripts/[0-9][0-9]-*.sh; do
  component="$(component_of "$script")"
  if [[ -n "$ONLY" ]] && ! in_list "$component" "$ONLY" && [[ "$component" != prereqs ]]; then continue; fi
  if [[ -n "$SKIP" ]] && in_list "$component" "$SKIP"; then log "skipping $component"; continue; fi
  log "==> $component"
  if bash "$script"; then
    log "<== $component done"
  else
    warn "$component failed, continuing with the next component"
    failed+=("$component")
  fi
done

echo
if [[ ${#failed[@]} -gt 0 ]]; then
  warn "components that failed: ${failed[*]}"
  warn "fix the cause and rerun: sudo ./install.sh --only $(IFS=,; echo "${failed[*]}")"
  exit 1
fi
log "all components installed. Credentials are in .env (mode 600) and in each tool's first-run file."
log "see README.md for the post-install checklist (Vault init, Nexus admin password, Jenkins unlock)."
