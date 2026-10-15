#!/usr/bin/env bash
# DevSecOps platform installer. Runs every scripts/NN-<component>.sh in order.
#
#   sudo ./install.sh                  install everything
#   sudo HOST_ADDRESS=10.0.0.20 DATA_ROOT=/data ./install.sh   same, settings given on the command line
#   sudo ./install.sh --list           show components in run order
#   sudo ./install.sh --only gitea,jenkins
#   sudo ./install.sh --skip gitea
#   sudo ./install.sh --only gitea,jenkins,sonarqube,nexus   strict minimum, with INGRESS=ports in .env
#   sudo ./install.sh --uninstall sonarqube   stop one stack (data is kept)
#   sudo ./install.sh --uninstall all         stop every stack (data is kept)
#   sudo ./install.sh --purge [--yes]         stop every stack and delete its data, network, images and wrappers

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib/common.sh
source lib/common.sh

usage() { sed -n '2,12p' "$0"; exit "${1:-0}"; }

component_of() { local f; f="$(basename "$1" .sh)"; printf '%s' "${f#*-}"; }

list_components() {
  for s in scripts/[0-9][0-9]-*.sh; do printf '%s\n' "$(component_of "$s")"; done
}

in_list() { local needle="$1" list=",$2,"; [[ "$list" == *",$needle,"* ]]; }

ONLY="" SKIP="" UNINSTALL="" PURGE=0 YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) list_components; exit 0 ;;
    --only) ONLY="$2"; shift 2 ;;
    --skip) SKIP="$2"; shift 2 ;;
    --uninstall) UNINSTALL="$2"; shift 2 ;;
    --purge) PURGE=1; shift ;;
    --yes) YES=1; shift ;;
    -h|--help) usage 0 ;;
    *) warn "unknown argument $1"; usage 1 ;;
  esac
done

require_root
require_cmd curl
require_cmd openssl

if [[ -n "$UNINSTALL" ]]; then
  load_env
  if [[ "$UNINSTALL" == all ]]; then
    for stack in $(stacks_in_reverse_order); do compose_down "$stack"; done
  else
    compose_down "$UNINSTALL"
  fi
  exit 0
fi

if [[ "$PURGE" == 1 ]]; then
  load_env
  warn "this stops every stack and deletes ${DATA_ROOT} (repositories, databases, artifacts, certificates),"
  warn "the ${DOCKER_NETWORK} network, the built Jenkins images and the scanner wrappers. .env is kept."
  if [[ "$YES" != 1 ]]; then
    [[ -t 0 ]] || die "not a terminal: pass --yes to purge without the prompt"
    read -r -p "type 'delete everything' to continue: " answer
    [[ "$answer" == "delete everything" ]] || die "aborted, nothing was changed"
  fi
  for stack in $(stacks_in_reverse_order); do compose_down "$stack"; done
  purge_host_state
  exit 0
fi

# The selected component list is passed to prereqs so its resource check matches what will run.
selected=()
for script in scripts/[0-9][0-9]-*.sh; do
  component="$(component_of "$script")"
  [[ "$component" == prereqs ]] && continue
  if [[ -n "$ONLY" ]] && ! in_list "$component" "$ONLY"; then continue; fi
  if [[ -n "$SKIP" ]] && in_list "$component" "$SKIP"; then continue; fi
  selected+=("$component")
done
INSTALL_COMPONENTS="$(IFS=,; echo "${selected[*]}")"
export INSTALL_COMPONENTS

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
