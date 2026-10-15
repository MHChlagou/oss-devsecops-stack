#!/usr/bin/env bash
# Gitea: source control, pull requests, webhooks to Jenkins. Light (about 512MB RAM) and
# configured entirely through GITEA__section__KEY environment variables.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_root
load_env
ensure_network
ensure_dir "$DATA_ROOT/gitea/db"
ensure_dir "$DATA_ROOT/gitea/data" 1000:1000
compose_up gitea
sync_db_password gitea gitea-db gitea "$GITEA_DB_PASSWORD"
wait_for_service gitea "$GITEA_HTTP_PORT" "$GITEA_URL" /api/healthz 300

# First admin account. INSTALL_LOCK=true skips the web installer, so the account is created here.
# Idempotent: skipped when the user already exists.
ADMIN_USER=gitea_admin
if docker exec -u git gitea gitea admin user list --admin 2>/dev/null | awk 'NR>1 {print $2}' | grep -qx "$ADMIN_USER"; then
  log "admin user $ADMIN_USER already exists"
else
  log "creating admin user $ADMIN_USER (password GITEA_ADMIN_PASSWORD in .env, must be changed at first login)"
  docker exec -u git -e GITEA_ADMIN_PASSWORD="$GITEA_ADMIN_PASSWORD" -e ADMIN_EMAIL="$ADMIN_EMAIL" gitea \
    sh -c 'gitea admin user create --admin --username gitea_admin --email "$ADMIN_EMAIL" --password "$GITEA_ADMIN_PASSWORD" --must-change-password' >/dev/null
fi

log "Gitea: ${GITEA_URL}"
log "git over SSH: ssh://git@${GITEA_HOST}:${GITEA_SSH_PORT}/<org>/<repo>.git"
log "next: create an organisation, enable the Jenkins Gitea plugin server entry and point webhooks at ${JENKINS_URL}/gitea-webhook/post"
