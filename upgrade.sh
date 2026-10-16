#!/usr/bin/env bash
# Upgrades one component to the image versions pinned in versions.env, with a full backup first.
# The component is stopped during the backup and the restart; its data is never deleted.
#
#   sudo ./upgrade.sh gitea                      back up, upgrade, verify
#   sudo ./upgrade.sh nexus --yes                same, without the confirmation prompt
#   sudo ./upgrade.sh --list-backups
#   sudo ./upgrade.sh --rollback /srv/devsecops-backups/gitea-20261016-101500
#
# A backup is the component's data directory, databases included, archived while the component is
# stopped, plus the image versions it was running. BACKUP_ROOT (default /srv/devsecops-backups)
# lives outside DATA_ROOT, so ./install.sh --purge never deletes backups.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib/common.sh
source lib/common.sh

usage() { sed -n '2,13p' "$0"; exit "${1:-0}"; }

# Data directory under DATA_ROOT for each component; the stack name unless listed here.
data_dir_of() {
  case "$1" in
    dependency-track) printf 'dtrack' ;;
    *) printf '%s' "$1" ;;
  esac
}

install_script_of() {
  local script
  for script in scripts/[0-9][0-9]-"$1".sh; do
    [[ -f "$script" ]] && { printf '%s' "$script"; return 0; }
  done
  die "unknown component '$1' (./install.sh --list shows the names)"
}

# Image references of the stack's containers, running or stopped, as they were created.
current_images() {
  docker ps -a --filter "label=com.docker.compose.project=$1" --format '{{.Image}}' | sort -u
}

# Image references the stack would run with the current versions.env.
target_images() {
  compose "$1" config --images | sort -u
}

# Repository part of an image reference: everything before the tag (a colon after the last slash).
repo_of() {
  local ref="$1" last="${1##*/}"
  if [[ "$last" == *:* ]]; then printf '%s' "${ref%:*}"; else printf '%s' "$ref"; fi
}

tag_of() {
  local last="${1##*/}"
  if [[ "$last" == *:* ]]; then printf '%s' "${last##*:}"; else printf 'latest'; fi
}

# A new PostgreSQL major version cannot read the previous major's data directory: refuse.
check_postgres_major() {
  local old new old_major new_major
  old="$(grep -E '^(docker\.io/)?(library/)?postgres:' <<<"$1" | head -1 || true)"
  new="$(grep -E '^(docker\.io/)?(library/)?postgres:' <<<"$2" | head -1 || true)"
  [[ -n "$old" && -n "$new" ]] || return 0
  old_major="$(tag_of "$old" | grep -oE '^[0-9]+' || true)"
  new_major="$(tag_of "$new" | grep -oE '^[0-9]+' || true)"
  if [[ -n "$old_major" && -n "$new_major" && "$old_major" != "$new_major" ]]; then
    die "PostgreSQL ${old_major} -> ${new_major}: a new major version cannot read the existing database. Keep POSTGRES_IMAGE on ${old_major} (a major upgrade needs a dump and restore, see docs/upgrades.md)."
  fi
}

# For every image that changes, the versions.env variable to pin back on rollback: VAR=old-ref.
rollback_pins() {
  local old="$1" new="$2" ref repo previous var
  while read -r ref; do
    [[ -n "$ref" ]] || continue
    grep -qxF "$ref" <<<"$old" && continue
    repo="$(repo_of "$ref")"
    previous="$(while read -r o; do [[ "$(repo_of "$o")" == "$repo" ]] && printf '%s\n' "$o"; done <<<"$old" | head -1)"
    [[ -n "$previous" ]] || continue
    var="$(grep -hE "^[A-Z0-9_]+=${ref//./\\.}\$" "$VERSIONS_FILE" "$VERSIONS_LOCAL_FILE" 2>/dev/null | tail -1 | cut -d= -f1 || true)"
    [[ -n "$var" ]] && printf '%s=%s\n' "$var" "$previous"
  done <<<"$new"
  return 0
}

confirm() {
  [[ "$ASSUME_YES" == 1 ]] && return 0
  [[ -t 0 ]] || die "not a terminal: pass --yes to proceed without the prompt"
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" == y || "$answer" == Y ]] || die "aborted, nothing was changed"
}

indent() { local line; while IFS= read -r line; do printf '%s%s\n' "$1" "$line"; done; }

human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || printf '%s bytes' "$1"; }

cmd_upgrade() {
  local component="$1" script data_dir old new changed pins size avail stamp backup
  script="$(install_script_of "$component")"
  [[ -d "$STACKS_DIR/$component" ]] || die "$component has no stack to upgrade"
  data_dir="$(data_dir_of "$component")"
  [[ -d "$DATA_ROOT/$data_dir" ]] || die "no data at $DATA_ROOT/$data_dir: $component is not installed, use ./install.sh"

  old="$(current_images "$component")"
  [[ -n "$old" ]] || die "$component has no containers: nothing to upgrade, use ./install.sh --only $component"
  new="$(target_images "$component")"
  # Images built on this host (devsecops/...) are rebuilt by the install script, not pulled.
  changed="$(grep -vE '^devsecops/' <<<"$new" | grep -vxF -f <(printf '%s\n' "$old") || true)"
  if [[ -z "$changed" && "$FORCE" != 1 ]]; then
    log "$component already runs the versions pinned in versions.env:"
    indent '  ' <<<"$old"
    return 0
  fi
  check_postgres_major "$old" "$new"
  pins="$(rollback_pins "$old" "$new")"

  mkdir -p "$BACKUP_ROOT"
  chmod 700 "$BACKUP_ROOT"
  size="$(du -sb "$DATA_ROOT/$data_dir" | awk '{print $1}')"
  avail="$(df -B1 --output=avail "$BACKUP_ROOT" | tail -1 | tr -d ' ')"
  (( avail > size + size / 10 )) || die "not enough space in $BACKUP_ROOT: $(human "$avail") free, data is $(human "$size")"
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup="$BACKUP_ROOT/${component}-${stamp}"

  echo
  log "upgrade plan for $component"
  printf '  running now:\n'; indent '    ' <<<"$old"
  printf '  will run:\n'; indent '    ' <<<"$new"
  printf '  backup:    %s (%s of data, component stopped meanwhile)\n' "$backup" "$(human "$size")"
  printf '  rollback:  sudo ./upgrade.sh --rollback %s\n' "$backup"
  confirm "Proceed with the upgrade of $component?"

  log "pulling new images while $component keeps running"
  compose "$component" pull --ignore-buildable --quiet

  compose_down "$component"
  log "backing up $DATA_ROOT/$data_dir"
  mkdir -m 700 "$backup"
  tar --numeric-owner -czpf "$backup/data.tar.gz" -C "$DATA_ROOT" "$data_dir"
  {
    printf 'COMPONENT=%s\n' "$component"
    printf 'DATA_DIR=%s\n' "$data_dir"
    printf 'CREATED=%s\n' "$stamp"
  } > "$backup/meta.env"
  printf '%s\n' "$old" > "$backup/images-before.txt"
  printf '%s\n' "$pins" | sed '/^$/d' > "$backup/rollback-pins.env"
  log "backup written: $backup ($(human "$(stat -c %s "$backup/data.tar.gz")") compressed)"

  log "starting $component on the new versions (database migrations run now)"
  if bash "$script"; then
    echo
    log "$component upgraded:"
    current_images "$component" | sed 's/^/  /'
    log "check it in the browser; once satisfied, the backup can be deleted: sudo rm -r $backup"
  else
    warn "$component did not come up on the new versions; its data was migrated in place"
    warn "roll back to the backup taken a minute ago with:"
    warn "  sudo ./upgrade.sh --rollback $backup"
    exit 1
  fi
}

cmd_rollback() {
  local backup="${1%/}" component data_dir script aside stamp var
  [[ -f "$backup/meta.env" && -f "$backup/data.tar.gz" ]] || die "$backup is not a backup made by upgrade.sh"
  component="$(sed -n 's/^COMPONENT=//p' "$backup/meta.env")"
  data_dir="$(sed -n 's/^DATA_DIR=//p' "$backup/meta.env")"
  [[ "$component" =~ ^[a-z][a-z0-9-]*$ && "$data_dir" =~ ^[a-z][a-z0-9-]*$ ]] || die "unreadable metadata in $backup/meta.env"
  script="$(install_script_of "$component")"
  stamp="$(date +%Y%m%d-%H%M%S)"
  aside="$DATA_ROOT/${data_dir}.before-rollback-${stamp}"

  echo
  log "rollback plan for $component"
  printf '  restore:   %s/data.tar.gz into %s/%s\n' "$backup" "$DATA_ROOT" "$data_dir"
  printf '  current data kept aside as %s (not deleted)\n' "$aside"
  printf '  versions:  %s\n' "$(tr '\n' ' ' < "$backup/rollback-pins.env")"
  confirm "Proceed with the rollback of $component?"

  compose_down "$component" || true
  if [[ -d "$DATA_ROOT/$data_dir" ]]; then
    mv "$DATA_ROOT/$data_dir" "$aside"
  fi
  log "restoring data"
  tar --numeric-owner -xzpf "$backup/data.tar.gz" -C "$DATA_ROOT"

  # Pin the versions the restored data belongs to; versions.local.env overrides versions.env.
  touch "$VERSIONS_LOCAL_FILE"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    var="${line%%=*}"
    sed -i "/^${var}=/d" "$VERSIONS_LOCAL_FILE"
    printf '%s\n' "$line" >> "$VERSIONS_LOCAL_FILE"
  done < "$backup/rollback-pins.env"

  log "starting $component on the previous versions"
  bash "$script" || die "$component did not start after the rollback; data from before the rollback is in $aside"
  echo
  log "$component rolled back:"
  current_images "$component" | sed 's/^/  /'
  log "pins written to versions.local.env; remove those lines before the next upgrade of $component"
  log "the data from before the rollback is in $aside; delete it once satisfied"
}

cmd_list_backups() {
  local dir
  [[ -d "$BACKUP_ROOT" ]] || { log "no backups in $BACKUP_ROOT"; return 0; }
  for dir in "$BACKUP_ROOT"/*/; do
    [[ -f "$dir/meta.env" ]] || continue
    printf '%s  %s  %s\n' "${dir%/}" "$(du -sh "$dir" | awk '{print $1}')" "$(tr '\n' ' ' < "$dir/images-before.txt")"
  done
}

ASSUME_YES=0 FORCE=0 ACTION="" TARGET=""
BACKUP_ROOT="${BACKUP_ROOT:-/srv/devsecops-backups}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) ASSUME_YES=1; shift ;;
    --force) FORCE=1; shift ;;
    --list-backups) ACTION=list; shift ;;
    --rollback) ACTION=rollback; TARGET="${2:?--rollback needs a backup directory}"; shift 2 ;;
    -h|--help) usage 0 ;;
    -*) warn "unknown option $1"; usage 1 ;;
    *) [[ -z "$TARGET" ]] || usage 1; ACTION="${ACTION:-upgrade}"; TARGET="$1"; shift ;;
  esac
done
[[ -n "$ACTION" ]] || usage 1

require_root
require_cmd docker
load_env
case "$ACTION" in
  upgrade) cmd_upgrade "$TARGET" ;;
  rollback) cmd_rollback "$TARGET" ;;
  list) cmd_list_backups ;;
esac
