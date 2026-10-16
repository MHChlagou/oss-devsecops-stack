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
# Public certificate only, mounted read-only so Gitea trusts the platform when delivering
# webhooks. Refreshed on every run, so rerun this component after replacing the certificate.
ensure_dir "$DATA_ROOT/gitea/trust"
rm -f "$DATA_ROOT/gitea/trust/platform.crt"
if [[ "$INGRESS" == traefik && -f "$DATA_ROOT/traefik/certs/server.crt" ]]; then
  install -m 644 "$DATA_ROOT/traefik/certs/server.crt" "$DATA_ROOT/gitea/trust/platform.crt"
fi
# Gitea writes GITEA__* variables into app.ini but never removes keys. Gitea 28 moved the webhook
# allow-list to [security], so drop the key left in [webhook] by earlier versions. A 1.x image (after
# upgrade.sh --rollback) still reads that key, so it is kept there.
APP_INI="$DATA_ROOT/gitea/data/gitea/conf/app.ini"
GITEA_TAG="${GITEA_IMAGE##*:}"
if [[ "$GITEA_TAG" != 1.* && -f "$APP_INI" ]] && awk '/^\[/{s=$0} s=="[webhook]" && /^ALLOWED_HOST_LIST *=/{f=1} END{exit !f}' "$APP_INI"; then
  awk '/^\[/{s=$0} !(s=="[webhook]" && /^ALLOWED_HOST_LIST *=/)' "$APP_INI" > "$APP_INI.tmp"
  chown --reference="$APP_INI" "$APP_INI.tmp"
  chmod --reference="$APP_INI" "$APP_INI.tmp"
  mv "$APP_INI.tmp" "$APP_INI"
  log "removed the obsolete [webhook] ALLOWED_HOST_LIST from app.ini (now [security], strict egress)"
fi

compose_up gitea
sync_db_password gitea gitea-db gitea "$GITEA_DB_PASSWORD"
wait_for_service gitea "$GITEA_HTTP_PORT" "$GITEA_URL" /api/healthz 300

# First admin account. INSTALL_LOCK=true skips the web installer, so the account is created here.
# Idempotent across Gitea versions: create it, and treat "already exists" as success instead of
# parsing the CLI's user list. The password travels in the environment, never on a command line.
ADMIN_USER=gitea_admin
if create_output="$(docker exec -u git -e GITEA_ADMIN_PASSWORD="$GITEA_ADMIN_PASSWORD" -e ADMIN_EMAIL="$ADMIN_EMAIL" gitea \
    sh -c 'gitea admin user create --admin --username gitea_admin --email "$ADMIN_EMAIL" --password "$GITEA_ADMIN_PASSWORD" --must-change-password' 2>&1)"; then
  log "created admin user $ADMIN_USER (password GITEA_ADMIN_PASSWORD in .env, must be changed at first login)"
elif grep -q "already exists" <<<"$create_output"; then
  log "admin user $ADMIN_USER already exists"
else
  die "creating $ADMIN_USER failed: $create_output"
fi

log "Gitea: ${GITEA_URL}"
log "git over SSH: ssh://git@${GITEA_HOST}:${GITEA_SSH_PORT}/<org>/<repo>.git"
log "next: create an organisation, enable the Jenkins Gitea plugin server entry and point webhooks at ${JENKINS_URL}/gitea-webhook/post"
