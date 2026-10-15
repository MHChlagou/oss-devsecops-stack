# Keycloak

OpenID Connect identity provider. One login for Gitea, Jenkins, SonarQube, Nexus, DefectDojo,
Dependency-Track and Grafana, with group-based roles.

## Role in the chain

Without a central identity provider, each of seven tools keeps its own user list and nobody
removes accounts when people leave. Keycloak holds users and groups (or federates them from
the client's Active Directory or LDAP) and every tool trusts it through OIDC.

## Deployment

| Item | Value |
|---|---|
| Stack | `stacks/keycloak/docker-compose.yml`, installed by `scripts/20-keycloak.sh` |
| Images | `KEYCLOAK_IMAGE`, `POSTGRES_IMAGE` |
| Data | `${DATA_ROOT}/keycloak/db` (PostgreSQL) |
| URL | `https://<host>:8180/admin/` |
| First login | `admin` with `KEYCLOAK_ADMIN_PASSWORD` from `.env` |
| Budget | 0.5 vCPU, 1.5 GB |

Keycloak runs in production mode (`start`) with `KC_PROXY_HEADERS=xforwarded`, so it trusts
the `X-Forwarded-*` headers that Traefik sets and builds correct redirect URLs.

## First-run steps

1. Log in with the bootstrap admin. Keycloak 26 treats it as temporary: create a permanent
   admin user in the `master` realm, give it the `admin` role, then delete the bootstrap one.
2. Create a realm named `devsecops`. Keep `master` for Keycloak administration only.
3. Create groups that map to roles across tools: `platform-admins`, `developers`, `security`,
   `viewers`. Add a `groups` mapper to the client scope so the group list is in the token.
4. Optional: add a user federation (LDAP or Active Directory) so the client's accounts and
   passwords are reused, and enable TOTP as a required action for the admin groups.

## One OIDC client per tool

Create each client as confidential (client authentication on), standard flow only, with the
redirect URI below. Copy the client secret into the tool.

| Tool | Client ID | Redirect URI | Where to configure |
|---|---|---|---|
| Gitea | `gitea` | `https://<host>:3000/user/oauth2/keycloak/callback` | Site administration, Authentication sources, OAuth2, provider OpenID Connect, discovery URL `https://<host>:8180/realms/devsecops/.well-known/openid-configuration` |
| Jenkins | `jenkins` | `https://<host>:8080/securityRealm/finishLogin` | `oic-auth` plugin; add a `securityRealm: oic:` block to the JCasC file instead of the UI |
| SonarQube | `sonarqube` | `https://<host>:9000/oauth2/callback/oidc` | install the community OpenID Connect plugin into `${DATA_ROOT}/sonarqube/extensions/plugins`, configure under Administration, Authentication |
| Nexus | `nexus` | none (header based) | Nexus CE has no OIDC. Put the `traefik-forward-auth` or `oauth2-proxy` container in front of it, or keep local accounts for the few people who administer it |
| DefectDojo | `defectdojo` | `https://<host>:8083/complete/oidc/` | `DD_SOCIAL_AUTH_OIDC_AUTH_ENABLED=True`, `DD_SOCIAL_AUTH_OIDC_OIDC_ENDPOINT`, `DD_SOCIAL_AUTH_OIDC_KEY`, `DD_SOCIAL_AUTH_OIDC_SECRET` in the compose env; check names against `dojo/settings/settings.dist.py` of the pinned release |
| Dependency-Track | `dtrack` (public client, PKCE) | `https://<host>:8090/static/oidc-callback.html` | `ALPINE_OIDC_ENABLED=true`, `ALPINE_OIDC_ISSUER`, `ALPINE_OIDC_CLIENT_ID` on the API server, `OIDC_ISSUER` and `OIDC_CLIENT_ID` on the frontend |
| Grafana | `grafana` | `https://<host>:3001/login/generic_oauth` | `GF_AUTH_GENERIC_OAUTH_*` environment variables |

Switch one tool at a time, keep the local admin account of each tool as a break-glass login,
and test with a non-admin user before announcing it.

## Operations

- Backup: the PostgreSQL directory, or `docker exec keycloak-db pg_dump -U keycloak keycloak`.
  Realm exports (`kc.sh export`) are useful for rebuilding, not as the only backup.
- Upgrade: bump `KEYCLOAK_IMAGE` one minor version at a time, Keycloak migrates the schema on start.
- Logs: `docker logs keycloak-keycloak-1`. Login failures are at INFO level with the username.
- Session lifetimes, password policy and brute-force detection are per realm under Realm settings.

## Free edition notes

Keycloak has no paid tier. Red Hat sells a supported build under another name; the upstream
project has everything used here.
