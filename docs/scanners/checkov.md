# Checkov

Policy-as-code scanner for infrastructure definitions: Terraform, Kubernetes manifests, Helm,
Docker Compose, Dockerfiles, GitHub and GitLab CI files, and more.

## Where it runs

Pipeline stage 7, `checkov -d deploy`, only when infrastructure files changed. Findings upload
to DefectDojo. The stage starts in report-only mode in the example Jenkinsfile.

It also applies to this repository: `checkov -d stacks` reports the deliberate choices
(privileged cAdvisor, Docker socket mounts) which belong in a `.checkov.yaml` skip list with
a justification.

## Commands

```bash
checkov -d deploy
checkov -d deploy --framework kubernetes,dockerfile,docker_compose
checkov -d deploy --output cli --output json --output-file-path reports
checkov -f docker-compose.yml --check CKV_DOCKER_2,CKV_DOCKER_3     # a subset of checks
checkov -d deploy --soft-fail                                        # never fail the build
```

## Configuration

`.checkov.yaml` at the repository root:

```yaml
framework:
  - kubernetes
  - dockerfile
  - docker_compose
  - terraform
skip-check:
  - CKV_K8S_43   # image digests: we pin tags from Nexus, digests break the promotion flow
compact: true
quiet: true
```

Inline suppression: `# checkov:skip=CKV_K8S_8: liveness probe handled by the sidecar` on the
resource. Custom policies are YAML or Python files passed with `--external-checks-dir`.

## Reading results

Each failed check has an id, a resource, the file and line range, and a guide link. The
severities come from Bridgecrew's catalogue and are advisory; the client's own ranking (for
example anything about secrets or privileged containers is high) belongs in DefectDojo rules.

## Free edition and limits

Apache 2.0. Prisma Cloud (Palo Alto) is the paid platform around it; the CLI, the policies and
the output formats used here are free. Checkov downloads policy updates from its API when it
can reach the internet and otherwise runs with the bundled set.
