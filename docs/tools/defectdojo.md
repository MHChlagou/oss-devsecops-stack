# DefectDojo

Vulnerability management. Every scanner's report lands here, gets deduplicated, assigned, risk
accepted or fixed, and tracked over time.

## Role in the chain

Seven scanners produce seven report formats. Without a common inbox, findings sit in build
artifacts and nobody owns them. The `post` block of the pipeline uploads each report with
`/api/v2/import-scan/`, DefectDojo parses it into findings under a product and an engagement,
matches them against earlier imports, and gives the security lead one list to triage with
SLAs and metrics.

## Deployment

| Item | Value |
|---|---|
| Stack | `stacks/defectdojo/docker-compose.yml`, installed by `scripts/60-defectdojo.sh` |
| Images | `DEFECTDOJO_DJANGO_IMAGE` (uwsgi, celery worker, celery beat, initializer), `DEFECTDOJO_NGINX_IMAGE`, `POSTGRES_IMAGE`, `REDIS_IMAGE` |
| Data | `${DATA_ROOT}/defectdojo/db`, `${DATA_ROOT}/defectdojo/media` |
| URL | `https://<host>:8083` |
| First login | `admin` with `DEFECTDOJO_ADMIN_PASSWORD` from `.env` |
| Secrets | `DEFECTDOJO_SECRET_KEY` (sessions), `DEFECTDOJO_CREDENTIAL_AES_KEY` (encrypts stored credentials); losing the second one makes stored tool credentials unreadable |
| Budget | 2 vCPU under load, 3 GB |

The compose file mirrors the upstream layout: the `initializer` runs migrations and creates
the admin once, `uwsgi` serves the application, `celeryworker` parses uploads, `celerybeat`
runs scheduled jobs, `nginx` serves static files and proxies to uwsgi.

## First-run steps

1. Log in as `admin`. Create a product type per client and a product per application.
2. Create a service user `jenkins` with role "Writer" on the product type, generate its API
   key from the user menu (API v2 Key), store it in Jenkins as `defectdojo-api-key`.
3. System settings: enable deduplication, enable "Enforce SLA", set SLA days per severity
   (for example critical 7, high 30, medium 90), enable "Delete duplicates".
4. Notifications: email through the client's SMTP (`DD_EMAIL_URL`) or a webhook to their chat.

## Import model used by the pipeline

Each report is sent with `product_name`, `engagement_name=ci`, `auto_create_context=true`
(creates the product and engagement on first use) and `close_old_findings=true` (findings
absent from the new report are closed as fixed). Scan type names must match DefectDojo's
parser names exactly; the ones used in the example Jenkinsfile:

| Tool | `scan_type` | File |
|---|---|---|
| Gitleaks | `Gitleaks Scan` | JSON report |
| Semgrep | `SARIF` (or `Semgrep JSON Report`) | `--sarif` output |
| Trivy filesystem and image | `Trivy Scan` | `--format json` |
| Checkov | `Checkov Scan` | `results_json.json` |
| OWASP ZAP | `ZAP Scan` | XML or JSON report |
| SonarQube | `SonarQube API Import` | configured as a tool, pulls from the API |
| Dependency-Track | `Dependency Track Finding Packaging Format (FPF) Export` | optional, usually left in Dependency-Track |

Use `reimport-scan` instead of `import-scan` to update one test over time rather than create a
new test per build; the choice affects how metrics read. The full list of parsers is under
`/api/v2/doc/` on the instance.

## Operations

- Backup: PostgreSQL (`pg_dump -U defectdojo defectdojo` from the `defectdojo-db` container)
  and the `media` directory. Keep `.env` safe for the two keys.
- Upgrade: bump both DefectDojo images to the same version. The initializer applies migrations
  on the next start. Read the release notes; the project releases monthly.
- Logs: `docker compose -p defectdojo logs uwsgi celeryworker`.
- Scale: if imports queue, add a second `celeryworker` service or raise `DD_CELERY_WORKER_CONCURRENCY`.
- Login with Keycloak: see `keycloak.md`.

## Free edition notes

DefectDojo is BSD licensed. The company behind it sells a Pro edition and a hosted service with
extra reporting and integrations; everything the pipeline uses is in the open source build.
