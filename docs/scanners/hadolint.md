# hadolint

Dockerfile linter. Catches the mistakes that make images large, unreproducible or insecure
before the image is built.

## Where it runs

Pipeline stage 6, `hadolint Dockerfile`, before `docker build`. Fails the build on warnings
and errors by default; it takes a second.

## Commands

```bash
hadolint Dockerfile
hadolint --failure-threshold error Dockerfile      # only errors fail
hadolint -f json Dockerfile > hadolint.json
hadolint docker/*.Dockerfile
```

## What it checks

Unpinned base images (`FROM php` without a tag or digest), `apt-get install` without
`--no-install-recommends` or without cleaning the lists, `latest` tags, missing `USER` (root
at runtime), `ADD` where `COPY` is enough, `sudo`, secrets in `ENV`, multiple `CMD` lines, and
ShellCheck findings inside `RUN` lines. Rule ids are `DL` (Dockerfile) and `SC` (ShellCheck).

## Configuration

`.hadolint.yaml` at the repository root:

```yaml
ignored:
  - DL3008   # apt pin versions: we pin the base image digest instead
trustedRegistries:
  - <host>:5000
failure-threshold: warning
```

`trustedRegistries` makes hadolint complain about base images that do not come through
Nexus, which enforces the "everything through the proxy" rule from the Dockerfile up.
Inline: `# hadolint ignore=DL3018` on the line before an instruction.

## Free edition and limits

GPL-3.0, no paid edition. It lints the Dockerfile text only; what the image contains is
Trivy's job.
