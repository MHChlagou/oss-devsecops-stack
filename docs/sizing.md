# Sizing for five parallel builds

This page sets the minimum and recommended hardware for the stack when Jenkins runs five
builds at the same time (`JENKINS_MAX_AGENTS=5` in `.env`). The numbers are budgets, not
measurements of the client's code: they assume PHP and TypeScript applications of ordinary
size (up to a few hundred thousand lines, a Docker image under 1 GB). Measure after the
first month with Grafana (dashboards 1860 and 14282) and adjust.

## What one build costs

A pipeline from `templates/Jenkinsfile.example` runs these steps on one ephemeral agent.
Peak usage is what matters, because five agents reach their peaks at different moments but
the host must survive the worst case.

| Step | Peak CPU | Peak RAM | Disk churn | Typical time |
|---|---|---|---|---|
| composer install, npm ci | 1 vCPU | 1 GB | 0.5 to 2 GB of dependencies | 1 to 3 min (cold), 20 s (cached from Nexus) |
| npm build and unit tests | 2 vCPU | 1.5 to 2 GB | small | 1 to 5 min |
| Gitleaks | 1 vCPU | 300 MB | none | 10 to 30 s |
| Semgrep | 2 vCPU | 1 to 2 GB | none | 1 to 4 min |
| sonar-scanner | 1 vCPU | 1 GB (JVM) | none | 1 to 3 min, then queues in SonarQube |
| Trivy fs and Syft | 1 vCPU | 500 MB | 1 GB vulnerability DB (shared cache) | 30 s to 2 min |
| docker build and Trivy image | 2 vCPU | 1 GB | image layers, 1 to 3 GB | 2 to 6 min |
| ZAP baseline | 1 vCPU | 1 GB | small | 2 to 5 min |

Budget per agent: 2 vCPU sustained with bursts to 3, 4 GB RAM, 10 GB of workspace and
layer cache. The agent is destroyed after the build, so the disk is reclaimed, but the
Docker build cache and the scanner caches are shared volumes that grow over time.

Five agents: 10 vCPU, 20 GB RAM, 50 GB of transient disk.

## What the platform costs

Values are the configured JVM heaps or observed steady state, with the extra load that
five simultaneous pipelines add (five SonarQube analyses queued, five SBOM uploads, five
report imports into DefectDojo, image pushes to Nexus).

| Component | vCPU idle | vCPU under load | RAM | Persistent disk after a year |
|---|---|---|---|---|
| Traefik | 0.1 | 0.5 | 128 MB | logs only |
| Keycloak + PostgreSQL | 0.2 | 0.5 | 1.5 GB | 1 GB |
| Vault | 0.1 | 0.2 | 256 MB | under 1 GB |
| Gitea + PostgreSQL | 0.2 | 1 | 1.5 GB | repository size, plan 50 GB with LFS |
| Jenkins controller | 0.3 | 1.5 | 2.5 GB (heap 2 GB) | 20 GB of build logs and archived reports |
| SonarQube + PostgreSQL | 0.5 | 2.5 | 5 GB (web 1 GB, compute 2 GB, search 1 GB, DB 1 GB) | 30 GB |
| Nexus Repository CE | 0.3 | 2 | 4.5 GB (heap 2 GB, direct 2 GB) | 150 GB of proxied packages and images, prune with cleanup policies |
| DefectDojo (uwsgi, celery, PostgreSQL, Redis, nginx) | 0.3 | 2 | 3 GB | 20 GB |
| Dependency-Track + PostgreSQL | 0.5 | 2 | 5.5 GB (heap 4 GB, DB 1 GB) | 15 GB, plus the mirrored vulnerability databases |
| Prometheus, Grafana, Loki, Promtail, exporters | 0.5 | 1 | 2.5 GB | 40 GB at 30 days retention |
| Docker engine, OS, page cache | 0.5 | 1 | 3 GB | 30 GB |

Platform total: about 4 vCPU idle, 14 vCPU at full load, 30 GB RAM, 350 GB disk after a year.

## Totals

| Profile | vCPU | RAM | Disk | Layout |
|---|---|---|---|---|
| Minimum, five builds, single host | 16 | 48 GB | 500 GB SSD | everything on one Docker host; CPU is oversubscribed at full load, builds slow down but nothing fails |
| Recommended, five builds, single host | 24 | 64 GB | 1 TB NVMe | headroom for growth to 8 agents and for SonarQube and Dependency-Track heap increases |
| Recommended, five builds, two hosts | platform 8 / build 12 | platform 32 GB / build 32 GB | platform 500 GB / build 300 GB | Jenkins agents on a separate Docker host, see below |

The RAM figure is the one that must not be undersized: the JVMs (Jenkins, SonarQube, Nexus,
Dependency-Track) reserve their heaps regardless of load, and an out-of-memory kill on
PostgreSQL costs more than an hour of slow builds. CPU can be oversubscribed by half at
full load, which only lengthens builds.

`scripts/00-prereqs.sh` checks the host against 24 GB plus 4 GB per agent and 6 vCPU plus
2 vCPU per agent, and warns when the host is below.

## Why a second host is worth it

With one host, a build that goes wrong (a test suite that forks without limit, a `docker build`
that extracts a huge archive) competes with SonarQube and Gitea for the same memory. Moving
the agents to a second Docker host keeps the platform responsive and makes the build capacity
independent of the platform. The Jenkins Docker plugin talks to a remote engine over TLS:
point `dockerHost.uri` in `stacks/jenkins/controller/casc/jenkins.yaml` at
`tcp://build-host:2376` with client certificates, and run the socket proxy there instead.
Nothing else changes.

## Disk layout

- `${DATA_ROOT}` on SSD or NVMe. PostgreSQL (four instances) and SonarQube's Elasticsearch are
  latency sensitive; spinning disks make analyses time out.
- `/var/lib/docker` on the same class of disk, 200 GB minimum: image layers for every tool,
  the agent image, and the build cache of five concurrent `docker build` runs.
- Keep 20 percent free at all times. Nexus and Loki fail in confusing ways when the disk fills.
- Backups go to a different volume or host. Plan for 1.5 times the size of `${DATA_ROOT}`.

## Network

- 1 Gbit/s between the build host and the platform host when they are separate: five agents
  pulling base images and pushing built images at once saturate 100 Mbit/s.
- Outbound internet from the platform host for Docker Hub, npm, Packagist, the Trivy database
  on GitHub, the NVD and OSV feeds for Dependency-Track, and Semgrep's rule registry. If the
  client's network blocks this, Nexus proxies cover packages and images, and Trivy and
  Dependency-Track need a scheduled mirror job.
- One wildcard DNS record and inbound 80, 443 and the Gitea SSH port.

## Known bottlenecks at five parallel builds

- SonarQube Community Build runs one compute engine worker, so five analyses submitted together
  are processed one after another. At 1 to 3 minutes each, the last pipeline waits up to 15
  minutes at the quality gate. The example Jenkinsfile allows 20. If this is the daily
  pattern, stagger the triggers or accept the queue; more workers are a paid feature.
- Nexus Community Edition is capped at 200,000 requests per day. Five busy pipelines with
  cold caches make a few thousand requests per build; this is well within the cap, but check
  the counter under Administration, Support, Usage after the first weeks.
- Dependency-Track re-analyses every project when a vulnerability feed updates. With hundreds
  of projects this is CPU heavy at night; it does not affect daytime builds.
- DefectDojo imports are processed by one celery worker. Five simultaneous report uploads
  finish within a minute or two; raise the worker count in `stacks/defectdojo/docker-compose.yml`
  only if imports pile up.

## Scaling beyond five

Each extra agent costs 2 vCPU and 4 GB RAM on the build host and nothing on the platform until
about 15 agents, where SonarQube and Nexus need their heaps doubled. Change `JENKINS_MAX_AGENTS`
in `.env`, rerun `sudo ./install.sh --only jenkins`, and the Docker cloud cap follows.
