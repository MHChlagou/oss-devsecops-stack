# Trivy

Vulnerability, misconfiguration and secret scanner for filesystems, container images and
infrastructure files. Used twice in the pipeline.

## Where it runs

- Stage 4, `trivy fs` on the checkout: reads `composer.lock` and `package-lock.json`
  (or `yarn.lock`, `pnpm-lock.yaml`) and reports vulnerable dependencies; also scans for
  secrets and misconfigurations in the tree.
- Stage 6, `trivy image` on the freshly built image: OS packages of the base image plus the
  application dependencies inside it.

Both fail the build on HIGH and CRITICAL severities with `--exit-code 1`.

## Commands

```bash
trivy fs --scanners vuln,secret,misconfig .
trivy fs --severity HIGH,CRITICAL --exit-code 1 --format json --output trivy-fs.json .
trivy image <host>:5000/app:42
trivy image --ignore-unfixed --severity HIGH,CRITICAL --exit-code 1 app:42
trivy config deploy/           # Kubernetes, Compose, Terraform, Dockerfile misconfigurations
trivy sbom sbom.cdx.json       # scan an existing SBOM instead of the source
```

`--ignore-unfixed` hides findings with no upstream fix yet; useful for the gate, not for the
report, so run the report without it and the gate with it if the noise is high.

## Configuration

- `.trivyignore` at the repository root lists CVE ids to skip, one per line, with a comment
  and an expiry date reviewed monthly. `.trivyignore.yaml` supports per-path and dated entries.
- `trivy.yaml` sets defaults (severity, scanners, timeout) per repository.
- The vulnerability database is downloaded from GitHub's container registry on first run and
  refreshed every six hours. The host wrapper and the agent image share a cache volume, so five
  parallel builds do not download it five times.

## Reading results

Each finding has the package, installed version, fixed version and CVE with CVSS. Fix order:
bump the dependency in the lock file for application packages; rebuild on a newer base image
tag for OS packages (Trivy shows which base layer introduced it with `--format table` and the
layer digest).

## Free edition and limits

Apache 2.0, no paid edition of the scanner. Aqua sells a platform around it. Trivy knows
about Composer and npm lock files only, so a project that installs without a lock file
produces an empty dependency scan; commit the lock files.
