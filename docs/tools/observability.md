# Observability: Prometheus, Grafana, Loki

Metrics, logs and alerting for the platform itself. Not for the client's applications,
although it can be extended to them.

## Role in the chain

The chain fails quietly when it fails: a full disk stops Nexus accepting pushes, a sealed
Vault blocks every pipeline after a reboot, a SonarQube queue makes builds time out at the
quality gate. This stack turns those into dashboards and alerts.

## Deployment

| Item | Value |
|---|---|
| Stack | `stacks/observability/docker-compose.yml`, installed by `scripts/70-observability.sh` |
| Services | Prometheus (metrics, 30 days), node-exporter (host), cAdvisor (containers), Loki (logs, 30 days), Promtail (ships every container's stdout to Loki), Grafana |
| Config | `stacks/observability/prometheus/prometheus.yml`, `loki/loki.yml`, `promtail/promtail.yml`, `grafana/provisioning/` |
| Data | `${DATA_ROOT}/observability/{prometheus,loki,grafana}` |
| URLs | `https://<host>/grafana` (login `admin` with `GRAFANA_ADMIN_PASSWORD`), `https://<host>/prometheus` (behind the Traefik dashboard basic auth) |
| Budget | 1 vCPU, 2.5 GB, 40 GB disk |

Prometheus scrapes itself, node-exporter, cAdvisor, Traefik and the Jenkins Prometheus plugin.
Promtail discovers containers through the Docker socket and labels each log line with
`container`, `stack` (compose project) and `service`.

## First-run steps

1. Log in to Grafana. Datasources Prometheus and Loki are provisioned.
2. Import dashboards by ID: 1860 (Node Exporter Full), 14282 (cAdvisor), 17346 (Traefik),
   9964 (Jenkins performance and health).
3. Alerting, contact points: email through the client's SMTP or a webhook into their chat.
   Grafana alerting is free and replaces a separate Alertmanager.
4. Alert rules to start with:
   - disk on `${DATA_ROOT}` and `/var/lib/docker` above 80 percent;
   - host memory available below 10 percent for 10 minutes;
   - any container restarting more than 3 times in 15 minutes (cAdvisor `container_start_time_seconds`);
   - Vault sealed: `up{job="vault"}` once you add Vault's `/v1/sys/metrics` with a token, or a
     blackbox probe on `/v1/sys/health` returning 503;
   - Jenkins queue length above `JENKINS_MAX_AGENTS` for 30 minutes (builds are waiting for capacity).
5. Explore, Loki: `{stack="jenkins"} |= "ERROR"` is the quickest way to debug a failed component.

## Extending

- Add a scrape job per tool that exposes metrics: Nexus (`/service/metrics/prometheus`),
  Gitea (`/metrics` with `GITEA__metrics__ENABLED=true`), Keycloak (`/metrics` on the
  management port with `KC_METRICS_ENABLED=true`), Dependency-Track (`/metrics` with
  `ALPINE_METRICS_ENABLED=true`).
- The client's applications can push logs to Loki and metrics to Prometheus the same way; keep
  them in a separate Grafana organisation or folder.
- Blackbox exporter adds HTTP probes of every public URL, which catches certificate expiry.

## Operations

- Backup: Grafana's data directory (dashboards, users, alert rules). Prometheus and Loki data
  are operational history; back them up only if the client wants long trends.
- Retention: change `--storage.tsdb.retention.time` in the compose file and `retention_period`
  in `loki.yml`.
- Upgrade: bump the images; Grafana migrates its database on start, Prometheus and Loki are
  backwards compatible within a major version.
- cAdvisor runs privileged because it reads cgroups; it is read-only on the host filesystem.

## Free edition notes

Prometheus and Promtail are Apache 2.0. Grafana and Loki are AGPL, which is free for internal
use; Grafana Labs sells an enterprise edition and a cloud service with features not used here.
