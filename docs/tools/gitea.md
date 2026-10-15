# Gitea

Git hosting, pull requests, code review and webhooks. The entry point of the chain.

## Role in the chain

Developers push to Gitea. A webhook tells Jenkins to build. Branch protection on `main`
requires a passing Jenkins status and a review before merge, which is where the security
gates become mandatory rather than advisory.

## Why Gitea

GitHub has no free self-hosted edition and GitLab CE needs 4 GB of RAM and a dozen processes
for features this chain does not use (its own CI, registry, pages). Gitea does repositories,
reviews, webhooks, OIDC login, LFS and an API in one Go binary under 1 GB. Forgejo is a
compatible fork with the same configuration if the client prefers a community-governed project.

## Deployment

| Item | Value |
|---|---|
| Stack | `stacks/gitea/docker-compose.yml`, installed by `scripts/30-gitea.sh` |
| Images | `GITEA_IMAGE`, `POSTGRES_IMAGE` |
| Data | `${DATA_ROOT}/gitea/data` (repositories, LFS, attachments, `gitea/conf/app.ini`), `${DATA_ROOT}/gitea/db` |
| URL | `https://<host>:3000` |
| SSH | host port `GITEA_SSH_PORT` (2222), clone URLs advertise it automatically |
| First login | `gitea_admin` with `GITEA_ADMIN_PASSWORD` from `.env`, password change forced |
| Budget | 1 vCPU, 1.5 GB |

Configuration is injected as `GITEA__section__KEY` environment variables, which Gitea writes
into `app.ini` on first start. Settings chosen here:

- `INSTALL_LOCK=true`: the web installer is skipped, the admin account is created by the script.
- `DISABLE_REGISTRATION=true` and `REQUIRE_SIGNIN_VIEW=true`: no self-service accounts, no anonymous browsing.
- `actions.ENABLED=false`: Jenkins is the CI, Gitea Actions would be a second one.
- `webhook.ALLOWED_HOST_LIST=<host>`: webhooks may only call the platform host itself, which
  stops a repository admin from using Gitea to probe other internal services.
- `LFS_START_SERVER=true`: large files (design assets, fixtures) stay out of Git history.

## First-run steps

1. Log in as `gitea_admin`, change the password, add your SSH key.
2. Create an organisation per client team, with teams `owners`, `developers`, `reviewers`.
3. Create a repository, protect `main`: require pull request, one approval, status check
   `continuous-integration/jenkins/pr-merge` (the name the Jenkins Gitea plugin reports),
   block merges on outdated branches.
4. Configure the OIDC source once Keycloak is ready (see `keycloak.md`), then make
   `gitea_admin` a break-glass account with a long random password kept in Vault.

## Jenkins integration

The Jenkins `gitea` plugin is installed. In Jenkins: Manage Jenkins, System, Gitea Servers,
add `https://<host>:3000` with a Gitea access token (Settings, Applications in Gitea, scopes
`read:organization`, `read:repository`, `write:repository` for commit statuses). Tick "Manage
hooks" so Jenkins creates the webhooks itself. Then create a "Gitea Organization" job: every
repository with a Jenkinsfile gets a multibranch pipeline, and pull requests get built and
reported back as commit statuses.

Manual webhook, when needed: `https://<host>:8080/gitea-webhook/post`, content type JSON,
events push and pull request.

## Operations

- Backup: `docker exec -u git gitea gitea dump -c /data/gitea/conf/app.ini` writes a zip with
  repositories and a database dump into the container's working directory. Nightly, plus a
  snapshot of `${DATA_ROOT}/gitea`.
- Upgrade: bump `GITEA_IMAGE` by one minor version at a time and read the breaking-changes
  section of the release notes. Gitea migrates its database on start.
- Logs: `docker logs gitea`, level `Info`. Raise to `Debug` through `GITEA__log__LEVEL` only
  while investigating.
- Admin CLI: `docker exec -u git gitea gitea admin user list`, `... admin user change-password`,
  `... admin regenerate hooks` after changing `ROOT_URL`.
- Mirrors: Gitea can pull-mirror from GitHub or GitLab if the client migrates gradually.

## Free edition notes

Gitea is MIT licensed with no paid edition. The company behind it sells hosting and support,
nothing is held back from the self-hosted build.
