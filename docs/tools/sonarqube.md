# SonarQube Community Build

Static analysis for code quality and maintainability, with a quality gate that blocks the
pipeline. Covers PHP, JavaScript, TypeScript, HTML, CSS and the usual infrastructure files.

## Role in the chain

Stage 3 of the pipeline runs `sonar-scanner`, which uploads the analysis to SonarQube. The
compute engine processes it and evaluates the quality gate. `waitForQualityGate` in the
Jenkinsfile blocks until the result arrives through a webhook and fails the build on a red gate.

## Why this and what the free edition lacks

Community Build is the free, LGPL distribution. It analyses the main branch of each project
with the full rule sets for PHP and TypeScript, computes coverage and duplication, and
exposes an API and webhooks. It does not do branch or pull request analysis, and it has no
taint analysis (tracking user input to a dangerous sink), which is why Semgrep runs next to
it. It also runs a single compute engine worker, so five simultaneous analyses queue.

## Deployment

| Item | Value |
|---|---|
| Stack | `stacks/sonarqube/docker-compose.yml`, installed by `scripts/50-sonarqube.sh` |
| Images | `SONARQUBE_IMAGE` (`sonarqube:community`), `POSTGRES_IMAGE` |
| Data | `${DATA_ROOT}/sonarqube/data` (Elasticsearch index), `extensions` (plugins), `logs`, `db` |
| URL | `https://sonarqube.<DOMAIN>` |
| First login | `admin` / `admin`, password change forced |
| Heaps | web 1 GB, compute engine 2 GB, search 1 GB, set through `SONAR_*_JAVAOPTS` |
| Budget | 2.5 vCPU under load, 5 GB with PostgreSQL |

The host needs `vm.max_map_count=524288` (set by `scripts/00-prereqs.sh`) or the embedded
Elasticsearch refuses to start.

## First-run steps

1. Change the admin password. Under Administration, Security, disable "Anyone" permissions
   so projects are private by default.
2. Administration, Configuration, Webhooks: add `https://jenkins.<DOMAIN>/sonarqube-webhook/`.
   Without it `waitForQualityGate` times out.
3. My account, Security: create a token of type "Global analysis token" named `jenkins`,
   store it in Jenkins as secret text `sonarqube-token`.
4. In Jenkins, Manage Jenkins, System, SonarQube servers: name `sonarqube`, URL
   `https://sonarqube.<DOMAIN>`, token credential `sonarqube-token`. Or add the equivalent
   `sonarGlobalConfiguration` block to the JCasC file.
5. Quality gate: copy "Sonar way", add conditions on overall code for the first weeks
   (for example security rating A, no blocker issues), then switch to "new code" conditions
   once the historic debt is acknowledged.

## Project setup

Add `sonar-project.properties` to each repository:

```properties
sonar.projectKey=client-app
sonar.sources=src,resources/js
sonar.tests=tests
sonar.exclusions=vendor/**,node_modules/**,public/build/**
sonar.php.coverage.reportPaths=coverage/clover.xml
sonar.javascript.lcov.reportPaths=coverage/lcov.info
sonar.typescript.tsconfigPaths=tsconfig.json
```

Coverage reports come from PHPUnit (`--coverage-clover`) and Jest or Vitest (`lcov`) in the
build stage. SonarQube imports them, it does not run tests.

Reports from other tools can be imported as external issues: `sonar.sarifReportPaths` accepts
the Semgrep SARIF file, which puts Semgrep findings on the SonarQube issue list as well.

## Operations

- Backup: the PostgreSQL directory. The Elasticsearch index under `data/` is rebuilt from the
  database on start, so it can be excluded.
- Upgrade: the `community` tag moves. Pin a dated tag in `versions.env` before production
  (for example `sonarqube:25.4.0.105899-community`), and read the upgrade notes: the
  database schema migrates on start and cannot be rolled back.
- Plugins: drop jars into `${DATA_ROOT}/sonarqube/extensions/plugins` and restart. Useful
  ones: the community OpenID Connect plugin for Keycloak login, and the community branch
  plugin if the client insists on branch analysis without paying (it is unsupported upstream).
- Logs: `${DATA_ROOT}/sonarqube/logs/{web,ce,es}.log`.
- Housekeeping: Administration, Projects, Background tasks shows the queue. Administration,
  General, Database cleaner controls history retention.
