# Jenkins build agent with every scanner the pipeline needs. Binaries are copied from the
# official scanner images so no download script or checksum handling lives here.
ARG TRIVY_IMAGE
ARG GITLEAKS_IMAGE
ARG SYFT_IMAGE
ARG HADOLINT_IMAGE
FROM ${TRIVY_IMAGE} AS trivy
FROM ${GITLEAKS_IMAGE} AS gitleaks
FROM ${SYFT_IMAGE} AS syft
FROM ${HADOLINT_IMAGE} AS hadolint

FROM jenkins/agent:jdk21

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg git jq python3 python3-pip pipx \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && . /etc/os-release \
 && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin \
 && rm -rf /var/lib/apt/lists/*

COPY --from=trivy    /usr/local/bin/trivy /usr/local/bin/trivy
COPY --from=gitleaks /usr/bin/gitleaks    /usr/local/bin/gitleaks
COPY --from=syft     /syft                /usr/local/bin/syft
COPY --from=hadolint /bin/hadolint        /usr/local/bin/hadolint

# Platform TLS certificate(s), copied into certs/ by scripts/40-jenkins.sh when Traefik serves a
# self-signed or internal-CA certificate: trusted by the system store (git, curl) and by the
# JVM (plugins, SonarQube scanner). Empty directory when the platform runs in ports mode.
COPY certs/ /tmp/platform-certs/
RUN set -eu; for c in /tmp/platform-certs/*.crt; do \
      [ -f "$c" ] || continue; \
      name="platform-$(basename "$c" .crt)"; \
      cp "$c" "/usr/local/share/ca-certificates/${name}.crt"; \
      keytool -importcert -noprompt -trustcacerts -cacerts -storepass changeit -alias "$name" -file "$c"; \
      echo "trusted $name"; \
    done; \
    update-ca-certificates; \
    rm -rf /tmp/platform-certs

ENV PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin
RUN pipx install semgrep && pipx install checkov

USER jenkins
