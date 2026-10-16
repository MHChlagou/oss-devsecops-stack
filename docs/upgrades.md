# Upgrading components

Every image is pinned in `versions.env`, so nothing upgrades by surprise. An upgrade is a
deliberate change of one pin followed by `upgrade.sh`, which backs up the component's data
before the new version touches it.

## The procedure

```bash
cd /opt/oss-devsecops-stack
git pull                                   # brings the new pins and any configuration they need
sudo ./upgrade.sh gitea                    # one component at a time
```

`upgrade.sh <component>`:

1. Compares the images the component runs with the ones `versions.env` pins, and stops if they
   already match.
2. Refuses a PostgreSQL major version change (see below).
3. Checks free space for the backup and prints the plan, then asks for confirmation (`--yes`
   skips the prompt).
4. Pulls the new images while the component still runs, so the downtime is only the backup
   and the restart.
5. Stops the component and archives its data directory, databases included, to
   `/srv/devsecops-backups/<component>-<date>/` (outside `DATA_ROOT`, so `install.sh --purge`
   never deletes backups). The archive is taken while the component is stopped, so it is
   consistent.
6. Starts the component on the new versions through its normal install script, which waits
   for it to be healthy. Database migrations run during this start.

Migrations are one-way: an older version cannot read data migrated by a newer one. If the new
version misbehaves, roll back to the backup:

```bash
sudo ./upgrade.sh --list-backups
sudo ./upgrade.sh --rollback /srv/devsecops-backups/gitea-20261016-103715
```

The rollback keeps the current data aside (`<data-dir>.before-rollback-<date>`, never deleted
by the script), restores the archive, pins the previous image versions in `versions.local.env`
(git-ignored, overrides `versions.env`) and starts the component. Remove those pins from
`versions.local.env` before the next upgrade attempt. Once an upgrade is confirmed good,
delete its backup and any `.before-rollback-*` directory by hand.

## Per component

| Component | Notes |
|---|---|
| Gitea | Migrates its database on first start, directly across several releases (1.23 to 28.1 was tested with real data, then rolled back and upgraded again). Also: `gitea dump` for an extra portable backup. |
| Nexus | Migrates its embedded database on first start. Community Edition refuses uploads and pushes until the EULA is accepted in the first-login wizard or through the API; the acceptance survives upgrades. |
| Jenkins | Change `JENKINS_IMAGE` and run `stacks/jenkins/controller/lock-plugins.sh` so the plugin lock matches the new core, then `upgrade.sh jenkins`. |
| SonarQube | Check that the plugins in `extensions/plugins` support the new Community Build. The database migrates on first start. |
| PostgreSQL | Patch releases within a major (16.x) are safe and come with a normal upgrade. A new major cannot read the old data directory, so `upgrade.sh` refuses it. A major upgrade means `pg_dump` from the old version, a fresh data directory, and a restore into the new one; PostgreSQL 16 is supported until November 2028, so there is no hurry. |
| Traefik | Stores no data except the certificate; the tag follows patch releases of its minor line. |

## Gitea 28 changes taken care of

Gitea 28 replaced the webhook allow-list (`[webhook] ALLOWED_HOST_LIST`) with a global egress
policy (`[security] EGRESS_MODE` and `ALLOWED_HOST_LIST`). In the default `lax` mode every
public address is allowed, which would have widened what webhooks can reach on a host with a
public IP. The stack sets `EGRESS_MODE = strict` with the platform host as the only target,
and the Gitea step removes the obsolete key from `app.ini`. A webhook to any other address
fails with "denied by egress policy".

Gitea 1.26 also started deriving links from request headers by default
(`PUBLIC_URL_DETECTION = auto`). The stack sets `never`, so links, clone URLs and redirects
always come from `ROOT_URL` and keep the `/gitea` sub-path.
