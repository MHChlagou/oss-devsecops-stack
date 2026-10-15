# Documentation

- [Strict minimum](strict-minimum.md): Gitea, Jenkins, SonarQube and Nexus on host ports with no
  reverse proxy, for a pilot or behind the client's existing proxy.
- [Minimal setup](minimal-setup.md): Jenkins, Gitea, Nexus and SonarQube only, with its
  resource budget, minimum hosts and monthly cost on AWS, Azure, Google Cloud and a dedicated provider.
- [Sizing for five parallel builds](sizing.md): per-build and per-service budgets, minimum and
  recommended hosts, single-host versus two-host layout, known bottlenecks.

## Platform components

| Page | What it covers |
|---|---|
| [Traefik](tools/traefik.md) | one TLS port per tool, generated or client certificate, adding a service |
| [Keycloak](tools/keycloak.md) | realm and group design, one OIDC client per tool with redirect URIs |
| [Vault](tools/vault.md) | init and unseal procedure, AppRole for Jenkins, backup caveats |
| [Gitea](tools/gitea.md) | hardening settings, branch protection, Jenkins integration, dump and restore |
| [Jenkins](tools/jenkins.md) | JCasC, ephemeral Docker agents, agent image contents, credentials, plugins, security model |
| [SonarQube Community Build](tools/sonarqube.md) | quality gate, webhook, tokens, project properties, free edition limits |
| [Nexus Repository CE](tools/nexus.md) | repositories to create, Docker registry connector, usage caps, cleanup |
| [DefectDojo](tools/defectdojo.md) | import model, scan type names, SLAs, deduplication |
| [Dependency-Track](tools/dependency-track.md) | SBOM upload, vulnerability sources, policies, VEX workflow |
| [Observability](tools/observability.md) | dashboards, alert rules to start with, extending to more tools |

## Scanners

[Overview and fail-or-warn policy](scanners/README.md), then one page each:
[Gitleaks](scanners/gitleaks.md), [Semgrep](scanners/semgrep.md), [Trivy](scanners/trivy.md),
[Syft](scanners/syft.md), [hadolint](scanners/hadolint.md), [Checkov](scanners/checkov.md),
[KICS](scanners/kics.md), [OWASP ZAP](scanners/zap.md).

Every page follows the same outline: role in the chain, deployment facts (stack, data, URL,
first login, resource budget), first-run steps, integration with the other tools, operations
(backup, upgrade, logs) and what the free edition does not do.
