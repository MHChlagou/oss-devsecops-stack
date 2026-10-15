# Nexus Repository Community Edition

Artifact repository. Proxies and caches npm, Composer and Docker Hub, hosts the images the
pipeline builds, and becomes the only place builds fetch from.

## Role in the chain

Stage 2 pulls dependencies through Nexus proxies, which makes builds reproducible, fast and
independent of upstream outages. Stage 6 pushes the built image to the hosted Docker
repository at `<host>:5000`, where the deployment pulls it. Every artifact that reaches
staging has passed through a scan on the way in.

## Free edition limits

Nexus Repository Community Edition replaced the old OSS build in 2025. It is free for
production use with a cap of 100,000 components and 200,000 requests per day per instance,
visible under Administration, Support, Usage. Beyond that, uploads are blocked until the
count drops or a licence is bought. A single client with a handful of projects stays far below
both numbers; a cleanup policy on proxied packages keeps it that way.

Composer support comes from the community `nexus-repository-composer` format, proxy only.
Check whether the pinned `NEXUS_IMAGE` bundles it (Create repository shows "composer (proxy)").
If it does not, keep Packagist direct through an HTTP proxy, or run Repman or Satis.

## Deployment

| Item | Value |
|---|---|
| Stack | `stacks/nexus/docker-compose.yml`, installed by `scripts/55-nexus.sh` |
| Image | `NEXUS_IMAGE` |
| Data | `${DATA_ROOT}/nexus/data` (database, blob stores, logs) |
| URLs | `https://<host>:8081` (UI and package repositories), `https://<host>:5000` (Docker connector on port 5000) |
| First login | `admin`, password in `${DATA_ROOT}/nexus/data/admin.password`, change forced, file deleted afterwards |
| Heap | 2 GB heap, 2 GB direct memory (`INSTALL4J_ADD_VM_PARAMS`) |
| Budget | 2 vCPU under load, 4.5 GB |

## First-run steps

1. Log in, set the new admin password, disable anonymous access.
2. Security, Realms: activate "Docker Bearer Token Realm".
3. Repositories to create:
   - `npm-proxy` (remote `https://registry.npmjs.org`), `npm-hosted`, `npm-group` with both.
   - `composer-proxy` (remote `https://repo.packagist.org`) if the format exists.
   - `docker-proxy` (remote `https://registry-1.docker.io`, Docker Hub index), `docker-hosted`
     with HTTP connector port `5000`, `docker-group` with both. Traefik already serves port
     5000 with TLS, so pushes and pulls use `<host>:5000` over HTTPS, and the Traefik script
     trusts the certificate for the host's Docker daemon.
4. Security, Users: `ci` with role `nx-repository-view-*-*-*` plus `nx-repository-admin-docker-docker-hosted-edit`,
   store it in Jenkins as `nexus-registry` (or in Vault).
5. Cleanup policies: remove proxied components not downloaded for 90 days, and hosted images
   older than 20 versions per name. Attach them to the repositories and schedule the
   "Admin - Compact blob store" task weekly.

## Pointing builds at Nexus

In the Jenkins agent or in each project:

```ini
# .npmrc
registry=https://<host>:8081/repository/npm-group/
```

```json
// composer.json
"repositories": [{ "type": "composer", "url": "https://<host>:8081/repository/composer-proxy/" }],
"config": { "secure-http": true }
```

Docker: `docker login <host>:5000` on the agent, then `<host>:5000/<app>:<tag>`.
To pull base images through the proxy, set the Docker daemon's `registry-mirrors` to
`https://<host>:5000` on the build host, or reference `<host>:5000/library/php:8.3`
explicitly in Dockerfiles.

## Operations

- Backup: stop the container or use the "Admin - Export databases for backup" task, then copy
  `${DATA_ROOT}/nexus/data` excluding `cache/` and `tmp/`. Blob stores are large; back them up
  incrementally.
- Upgrade: bump `NEXUS_IMAGE`, one minor version at a time, and check the release notes for
  database migrations (3.7x moved from OrientDB to H2, which requires a migration step from
  older versions).
- Logs: `${DATA_ROOT}/nexus/data/log/nexus.log` and `request.log`.
- Monitoring: Administration, Support, Status; metrics at `/service/metrics/prometheus` with
  an admin token if you want them in Grafana.
