#!/usr/bin/env bash
# Jenkins: controller configured by JCasC, zero executors, builds run on ephemeral Docker agents
# created through a filtered Docker socket proxy. The agent image carries every scanner CLI.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_root
load_env
ensure_network
ensure_dir "$DATA_ROOT/jenkins/home" 1000:1000

# The platform certificate goes into both image build contexts so Jenkins, its plugins, git and
# the SonarQube scanner trust https://${HOST_ADDRESS}/... without manual truststore work.
# Rerun this component after replacing the certificate (docs/tls.md).
for ctx in controller agent; do
  rm -f "$STACKS_DIR/jenkins/$ctx/certs/"*.crt
  if [[ "$INGRESS" == traefik && -f "$DATA_ROOT/traefik/certs/server.crt" ]]; then
    cp "$DATA_ROOT/traefik/certs/server.crt" "$STACKS_DIR/jenkins/$ctx/certs/platform.crt"
  fi
done
[[ -f "$STACKS_DIR/jenkins/agent/certs/platform.crt" ]] && log "platform certificate will be trusted by the controller and agent images"

log "building agent image devsecops/jenkins-agent:local (scanner CLIs copied from their official images)"
docker build --quiet \
  --build-arg TRIVY_IMAGE="$TRIVY_IMAGE" \
  --build-arg GITLEAKS_IMAGE="$GITLEAKS_IMAGE" \
  --build-arg SYFT_IMAGE="$SYFT_IMAGE" \
  --build-arg HADOLINT_IMAGE="$HADOLINT_IMAGE" \
  -t devsecops/jenkins-agent:local "$STACKS_DIR/jenkins/agent" >/dev/null

compose_up jenkins --build
wait_for_service jenkins "$JENKINS_HTTP_PORT" "$JENKINS_URL" /login 300
log "Jenkins: ${JENKINS_URL} (user ${JENKINS_ADMIN_USER}, password JENKINS_ADMIN_PASSWORD in .env)"
log "pipelines use: agent { label 'docker-agent' }  (see templates/Jenkinsfile.example)"
