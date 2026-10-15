# Decisions

Short record of the choices that shaped the final setup, in the order they were made. Each
entry states the decision, the alternatives considered and the reason, so the next person
does not have to rediscover them.

## 1. Free, self-hosted tools only

Decision: every component is free for private self-hosted use (community or open-source
edition); licence type does not matter, price does.
Alternatives: GitLab Ultimate, SonarQube Developer, Nexus Lifecycle, Semgrep Pro.
Reason: the client has no licence budget. Consequences accepted: no branch analysis in
SonarQube Community (Semgrep covers pull requests), Nexus CE usage caps (100,000 components,
200,000 requests per day).

## 2. Gitea instead of GitLab

Decision: Gitea for source control.
Alternatives: GitLab CE, Forgejo, self-hosted GitHub (paid, excluded).
Reason: a fraction of GitLab's memory (about 0.5 GB against 4 to 6 GB), simpler to operate,
Jenkins stays the single CI. Forgejo is a drop-in replacement if Gitea's licensing changes.

## 3. Jenkins with ephemeral Docker agents, zero executors

Decision: the controller runs no builds; each build gets a throwaway container from a locally
built agent image that carries every scanner.
Alternatives: static agents, Gitea Actions, Kubernetes agents.
Reason: clean workspaces, scanner versions pinned in one Dockerfile, no second CI system. The
Docker socket is reached through a filtered proxy, which is still host-root-equivalent for
anyone who can define a pipeline; job creation is restricted to trusted users.

## 4. Four-tool core first, the rest later

Decision: install Traefik, Gitea, Jenkins, SonarQube and Nexus now; Keycloak, Vault,
DefectDojo, Dependency-Track and observability are installed one at a time when needed.
Reason: the pilot team is small; every deferred component has a cheap interim (Jenkins
credential store, archived reports, provider monitoring) and adds with `--only` without
touching what runs.

## 5. No DNS domain: host address and paths

Decision: tools are reached at `https://<host>/<tool>`, with `<host>` the server's IP.
Alternatives: hostname routing (`gitea.<domain>`, needs a wildcard DNS record), one port per
tool (`https://<host>:3000`, the first version of this installer).
Reason: the client did not want a DNS dependency, and one URL root per tool reads better than
port numbers. Tools that cannot run under a sub-path keep a port of their own (Docker
registry, Vault, DefectDojo, Dependency-Track). Known trade-off: the four tools share one
browser origin, so a script injection in one could reach another's session; acceptable for a
trusted team, reversible by hostname routing later.

## 6. Self-signed certificate for the host address

Decision: the installer generates a ten-year self-signed certificate for `HOST_ADDRESS` and
trusts it for the host's Docker daemon; the client's CA certificate replaces it by dropping
two files.
Alternatives: Let's Encrypt (impossible for an IP), no TLS (ports mode).
Reason: the only option that works with no DNS and no public CA while keeping passwords and
tokens off the wire. Browsers import the certificate once. Details in [tls.md](../tls.md).

## 7. Traefik 3.7

Decision: pin `traefik:v3.7`.
Reason: Docker Engine 29, which the prerequisites script installs, rejects the Docker API
version used by Traefik 3.5 and older; those versions start, bind every port and answer 404
for everything. Found during local verification before the client's first run.

## 8. Three parallel builds to start

Decision: `JENKINS_MAX_AGENTS=3` on a 24 vCPU, 62 GB host.
Reason: enough for the pilot team; the host can take five (about 37 GB and 14 vCPU for the
core profile) by changing one value in `.env` and rerunning Jenkins.

## 9. `.env` is the single source of truth

Decision: database role passwords are re-aligned from `.env` on every run; a new `.env`
next to existing data triggers a warning.
Reason: a lost or recreated `.env` generated new passwords while Postgres kept the old ones
and locked Gitea out, on the first real run. Postgres reads its password only when it
initialises an empty data directory.
