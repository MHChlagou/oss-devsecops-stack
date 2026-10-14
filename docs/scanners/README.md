# Scanners

Eight command-line scanners cover the pipeline stages. Each is available in two identical
forms, pinned to the same version in `versions.env`:

- inside the Jenkins agent image `devsecops/jenkins-agent:local`, used by the pipeline;
- as a wrapper in `/usr/local/bin` on the platform host, installed by `scripts/80-scanners.sh`,
  which runs the official image against the current directory with the caller's uid.

| Scanner | Stage | Finds | DefectDojo scan type |
|---|---|---|---|
| [Gitleaks](gitleaks.md) | pre-commit, 1 | secrets in Git history and staged files | `Gitleaks Scan` |
| [Semgrep](semgrep.md) | 3 | code-level security bugs, taint flows, bad patterns | `SARIF` |
| [Trivy](trivy.md) | 4, 6 | vulnerable packages, OS packages in images, misconfigurations, secrets | `Trivy Scan` |
| [Syft](syft.md) | 5 | nothing; produces the SBOM for Dependency-Track | none |
| [hadolint](hadolint.md) | 6 | Dockerfile mistakes | none (fails the build) |
| [Checkov](checkov.md) | 7 | insecure Terraform, Kubernetes, Compose, Dockerfile settings | `Checkov Scan` |
| [KICS](kics.md) | 7 (alternative) | same scope as Checkov, different rule set | `KICS Scan` |
| [OWASP ZAP](zap.md) | 9 | runtime web vulnerabilities on staging | `ZAP Scan` |

## Fail or warn

A scanner that fails the build on day one against an existing codebase blocks every team.
The example Jenkinsfile fails on Gitleaks (a leaked secret is always urgent), on Trivy HIGH
and CRITICAL, on hadolint, and on the SonarQube quality gate. Semgrep, Checkov and ZAP upload
their findings and continue. Tighten each one per project once its backlog is clean, and
keep the exceptions in version-controlled ignore files rather than in pipeline flags.

## Offline networks

Trivy, Semgrep and Checkov download databases or rules at run time. Behind a strict proxy,
mirror the Trivy database (`trivy image --download-db-only` on a connected host, copy the
cache directory), vendor the Semgrep rules into a repository and pass `--config` with a path,
and let Checkov run with its built-in policies only.
