# Jenkins

Continuous integration and delivery server. Runs the pipeline that strings every scanner
together and enforces the gates.

## Role in the chain

Gitea triggers Jenkins. Jenkins checks the code out on a throwaway agent container, runs the
nine stages of `templates/Jenkinsfile.example`, uploads results to SonarQube, Dependency-Track,
Nexus and DefectDojo, and reports a commit status back to Gitea. Nothing runs on the controller.

## Deployment

| Item | Value |
|---|---|
| Stack | `stacks/jenkins/docker-compose.yml`, installed by `scripts/40-jenkins.sh` |
| Controller image | `devsecops/jenkins:local`, built from `stacks/jenkins/controller/Dockerfile` on top of `JENKINS_IMAGE`, with plugins from `plugins.txt` |
| Agent image | `devsecops/jenkins-agent:local`, built from `stacks/jenkins/agent/Dockerfile` |
| Socket proxy | `tecnativa/docker-socket-proxy`, the only thing that touches `/var/run/docker.sock` |
| Config | `stacks/jenkins/controller/casc/jenkins.yaml` (Configuration as Code), mounted read-only |
| Data | `${DATA_ROOT}/jenkins/home` |
| URL | `https://jenkins.<DOMAIN>` |
| First login | `JENKINS_ADMIN_USER` and `JENKINS_ADMIN_PASSWORD` from `.env` |
| Budget | controller 1.5 vCPU, 2.5 GB; each agent 2 vCPU, 4 GB; `JENKINS_MAX_AGENTS` agents at once |

## How builds run

The controller has zero executors. A Docker cloud named `local-docker` is configured in JCasC.
When a pipeline asks for `agent { label 'docker-agent' }`, the Docker plugin asks the socket
proxy to start a container from `devsecops/jenkins-agent:local` on the `jenkins-internal`
network, attaches to it, runs the build, and removes it. The cap is `JENKINS_MAX_AGENTS`.

The agent image contains: git, Docker CLI (pointed at the proxy through `DOCKER_HOST`),
Trivy, Gitleaks, Syft, hadolint (copied from their official images, same versions as
`versions.env`), Semgrep and Checkov (installed with pipx), Python 3 and jq. Language
toolchains are not in it on purpose: the pipeline runs `composer`, `node` and
`sonar-scanner` inside their own official images with `docker.image(...).inside`, so
each project picks its versions.

## Configuration as Code

Everything that would normally be clicked in Manage Jenkins lives in `jenkins.yaml`:
security realm, authorisation, CSRF, the Docker cloud and template, the instance URL.
The file supports `${ENV}` substitution, which is how the admin password and agent cap
arrive from `.env`. To change anything: edit the file, run `sudo ./install.sh --only jenkins`.
The UI still allows edits, but they are lost at the next restart unless added to the file.

Things to add to the file as the platform matures:

- `securityRealm: oic:` for Keycloak login (plugin `oic-auth` is installed).
- `unclassified.sonarGlobalConfiguration` with the SonarQube server and token credential.
- `unclassified.giteaServers` with the Gitea URL and token credential.
- `unclassified.hashicorpVault` with the Vault URL and the AppRole credential.
- `credentials:` block that references Vault or environment variables, never literal secrets.

## Credentials the example pipeline expects

| ID | Kind | Source |
|---|---|---|
| `sonarqube-token` | secret text | SonarQube, My account, Security, token of type Global analysis |
| `dtrack-api-key` | secret text | Dependency-Track, Administration, Access management, Teams, automation team |
| `defectdojo-api-key` | secret text | DefectDojo, user menu, API v2 key |
| `nexus-registry` | username with password | Nexus user with `nx-repository-view-docker-*-*` privileges |

Long term these move to Vault (see `vault.md`) and the pipeline uses `withVault`.

## Plugins

`plugins.txt` pins the set: JCasC, Docker plugin and Docker pipeline, Pipeline, Git, Gitea,
credentials binding, matrix auth, OIDC, Vault, SonarQube scanner, Dependency-Track publisher,
Warnings Next Generation (renders Semgrep SARIF and Trivy in the build page), JUnit, HTML
publisher, timestamper, Prometheus metrics. Add a plugin by appending its short name and
rebuilding. The plugin manager in the UI works too but is lost on rebuild.

## Operations

- Backup: `${DATA_ROOT}/jenkins/home` nightly. Exclude `workspace/` and `caches/`. The
  JCasC file and `plugins.txt` are in Git, so a controller can be rebuilt from scratch.
- Upgrade: bump `JENKINS_IMAGE` (LTS line), rerun the component. Plugins update to the
  latest compatible versions at build time; pin versions in `plugins.txt` as `name:version`
  when reproducibility matters more than freshness.
- Logs: `docker logs jenkins`. Build logs are in the UI and under `jobs/*/builds/*/log`.
- Metrics: `/prometheus` is scraped by the observability stack; queue length and executor
  usage tell you when to raise `JENKINS_MAX_AGENTS`.
- Housekeeping: `buildDiscarder` in the Jenkinsfile keeps 30 builds; archived reports are
  the main disk consumer.

## Security notes

- Anyone who can define a pipeline can ask the Docker plugin to start a container with any
  options, including a privileged one with the host filesystem mounted. The socket proxy
  limits the API surface, not this. Restrict who can create or edit jobs (matrix auth,
  groups from Keycloak), review Jenkinsfiles in pull requests like any code, and move agents
  to a dedicated build host or to Kubernetes when the client can provide one.
- The controller runs as uid 1000, has no Docker socket, and reaches the proxy only on the
  `jenkins-internal` network.
- Script approval stays enabled. Shared libraries should come from a protected Gitea repository.
- Rotate `JENKINS_ADMIN_PASSWORD` by changing `.env` and rerunning; JCasC applies it on restart.
