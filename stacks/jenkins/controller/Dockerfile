ARG JENKINS_IMAGE
FROM ${JENKINS_IMAGE}

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && . /etc/os-release \
 && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin \
 && rm -rf /var/lib/apt/lists/*

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
USER jenkins

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
