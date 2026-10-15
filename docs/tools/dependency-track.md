# Dependency-Track

Software bill of materials (SBOM) platform. Keeps the component inventory of every build and
re-checks it against new vulnerability disclosures, every day, without rebuilding anything.

## Role in the chain

Trivy answers "is this build vulnerable right now". Dependency-Track answers "which of the
applications we shipped last year contain the library that was disclosed this morning". Stage 5
generates a CycloneDX SBOM with Syft and the Jenkins plugin uploads it; Dependency-Track
tracks versions per project, applies licence and vulnerability policies, and notifies.

## Deployment

| Item | Value |
|---|---|
| Stack | `stacks/dependency-track/docker-compose.yml`, installed by `scripts/65-dependency-track.sh` |
| Images | `DTRACK_API_IMAGE`, `DTRACK_FRONTEND_IMAGE`, `POSTGRES_IMAGE` |
| Data | `${DATA_ROOT}/dtrack/data` (vulnerability database mirrors, indexes), `${DATA_ROOT}/dtrack/db` |
| URLs | `https://<host>:8090` (frontend), `https://<host>:8091` (API server, used by the frontend's browser code and by Jenkins) |
| First login | `admin` / `admin`, password change forced |
| Heap | 4 GB (`EXTRA_JAVA_OPTIONS`), the documented minimum |
| Budget | 2 vCPU under load, 5.5 GB; CPU heavy at night when feeds update |

The frontend is a static application that calls the API server from the browser, which is why
the API has its own port and CORS is enabled for the frontend origin.

## First-run steps

1. Log in, change the admin password.
2. Administration, Access Management, Teams: create `jenkins` with permissions
   `BOM_UPLOAD`, `PROJECT_CREATION_UPLOAD`, `VIEW_PORTFOLIO`, `VIEW_VULNERABILITY`; create an
   API key, store it in Jenkins as `dtrack-api-key`.
3. In Jenkins, Manage Jenkins, System, Dependency-Track: URL `https://<host>:8091`,
   API key credential, tick "Auto create projects". The `dependencyTrackPublisher` step in the
   example Jenkinsfile then works.
4. Administration, Analyzers: keep OSS Index and the internal analyzer on; add a free NVD API
   key (request it from the NVD site) so the initial mirror finishes in minutes instead of hours;
   add a GitHub token for the GitHub Advisories source. OSV is enabled under Vulnerability Sources.
5. Policies: create one that fails on any `critical` vulnerability with an available fix and one
   that flags copyleft licences the client does not accept. Policy violations show on the
   project and can gate the pipeline through the plugin's `failedTotalCritical` thresholds.
6. Notifications: Administration, Notifications, add an email or webhook rule for
   `NEW_VULNERABILITY` and `POLICY_VIOLATION` on the whole portfolio.

## Reading the data

Projects, one per application, with versions per branch. The component view lists every
library with its licence and known vulnerabilities; the audit view lets the security lead
mark a vulnerability as not affected with a justification, which is the VEX workflow that
auditors increasingly ask for. The portfolio dashboard shows the inherited risk score over time,
a useful number to report to the client monthly.

## Operations

- Backup: PostgreSQL. The `data/` directory holds mirrors that rebuild themselves.
- Upgrade: bump both images to the same version; schema migrates on start. Major versions
  (4 to 5) have a separate migration guide.
- Logs: `docker logs dtrack-api`.
- Air-gapped networks: Dependency-Track needs the NVD, OSV and GitHub feeds. Without outbound
  access, mirror them with a scheduled job on a connected host and set the mirror URLs.

## Free edition notes

Dependency-Track is Apache 2.0 with no paid edition; it is an OWASP flagship project.
