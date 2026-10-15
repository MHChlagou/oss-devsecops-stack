# TLS certificates

How the platform's certificate is created, where it is used, how long it lives, how to trust
it, and when and how to replace it. `<host>` is `HOST_ADDRESS` from `.env`, the server's name
or IP.

## What the installer does

`scripts/10-traefik.sh` runs once per install and, on its first run, generates a self-signed
certificate for `<host>`:

| Item | Value |
|---|---|
| Files | `${DATA_ROOT}/traefik/certs/server.crt` (public, mode 644) and `server.key` (private, mode 600, owned by root) |
| Subject | `CN=<host>` |
| Subject alternative names | `IP:<host>` when `HOST_ADDRESS` is an IPv4 address, otherwise `DNS:<host>`; plus `DNS:localhost` and `IP:127.0.0.1` for the installer's own health checks |
| Key and signature | RSA 2048, SHA-256 |
| Validity | 10 years from generation |
| Declared to Traefik | `${DATA_ROOT}/traefik/dynamic/tls.yml` as the default certificate, so every TLS entry point serves it: 443 and the dedicated ports of the registry (5000), Vault (8200), DefectDojo (8083) and Dependency-Track (8090, 8091) |
| Docker trust | copied to `/etc/docker/certs.d/<host>:5000/ca.crt`, so the host's Docker daemon, and therefore every Jenkins build agent, pushes to and pulls from the Nexus registry without an insecure-registry setting |

On every later run the script finds the two files and keeps them. It never overwrites a
certificate, whether generated or provided by the client.

Check the one on your server at any time:

```bash
sudo openssl x509 -in /srv/devsecops/traefik/certs/server.crt -noout -subject -ext subjectAltName -enddate
# or from any machine
echo | openssl s_client -connect <host>:443 2>/dev/null | openssl x509 -noout -subject -enddate
```

## Lifetime and renewal

There is no automatic renewal, and none is needed for ten years. Public certificate
authorities, Let's Encrypt included, do not issue certificates for a bare IP address or a
private hostname, so the ACME machinery that renews certificates every 90 days does not
apply to this setup. Should the client later give the host a public DNS name, Traefik's ACME
resolver can be added to `scripts/10-traefik.sh`; until then the generated certificate is
the right tool.

Regenerate by hand in three situations: `HOST_ADDRESS` changes (new IP, or a name instead of
the IP), the private key may have leaked, or the expiry date approaches. The procedure is the
same:

```bash
sudo rm /srv/devsecops/traefik/certs/server.crt /srv/devsecops/traefik/certs/server.key
sudo ./install.sh --only traefik
```

The Traefik step issues a new certificate for the current `HOST_ADDRESS`, reloads it (the
dynamic file provider watches the directory, so Traefik picks it up without a restart) and
refreshes the Docker trust copy. Then redistribute `server.crt` to every place listed in the
next section: the old copies no longer match.

If `HOST_ADDRESS` itself changed, also rerun the tools so their public URLs follow:
`sudo ./install.sh --only traefik,gitea,jenkins,sonarqube,nexus`.

## Trusting the certificate

A self-signed certificate is only as useful as the number of clients that trust it.
Everything below is a one-time copy of `server.crt`, which is public and safe to send by any
channel. Fetch it from the server with
`scp root@<host>:/srv/devsecops/traefik/certs/server.crt .`

### Browsers

Until the certificate is imported, every tool shows a warning once per browser. Import it
as a trusted certificate:

- Windows: double-click `server.crt`, Install Certificate, Local Machine, place in "Trusted
  Root Certification Authorities". Chrome and Edge use that store.
- macOS: open Keychain Access, drag `server.crt` into System, double-click it, Trust, "Always
  Trust". Safari and Chrome use the keychain.
- Linux (Debian, Ubuntu): `sudo cp server.crt /usr/local/share/ca-certificates/devsecops.crt &&
  sudo update-ca-certificates`. Chrome uses the system store; Firefox has its own, see below.
- Firefox on any OS: Settings, Privacy and Security, Certificates, View Certificates,
  Authorities, Import, tick "Trust this CA to identify websites". Or set
  `security.enterprise_roots.enabled` to true in `about:config` to use the system store.

### Git command line

Git verifies HTTPS remotes with its own CA bundle or the system store depending on the
platform, so a clone fails with "SSL certificate problem: self-signed certificate" until one
of the following is done. Pick one per developer machine.

Quickest, to be able to clone right away: skip verification for the platform host only.
Git applies the setting to that URL prefix and keeps verifying every other remote:

```bash
git config --global http.https://<host>/.sslVerify false
```

The plain `git config --global http.sslVerify false` also works, but it disables certificate
checks for every HTTPS remote on that machine, GitHub and package mirrors included, so prefer
the scoped form above.

Better, once the certificate has been fetched: tell Git to trust it, so verification stays on:

```bash
git config --global http.https://<host>/.sslCAInfo /path/to/server.crt
```

Importing the certificate system-wide, as in the browser section, also covers Git on Linux
and macOS.

Clones over SSH (`ssh://git@<host>:2222/...`) do not involve the certificate at all.

### Docker clients

The build host is done by the installer. Any other machine that pushes to or pulls from
`<host>:5000` copies the certificate to the same path; no daemon restart is needed:

```bash
sudo install -D -m 644 server.crt /etc/docker/certs.d/<host>:5000/ca.crt
```

### Tools calling each other through the public URL

The tools reach each other over the Docker network `devsecops` by container name, and those
internal addresses are plain HTTP, so they do not need the certificate. Use them wherever a
tool asks for another tool's address:

| From | To | Internal address to configure |
|---|---|---|
| Jenkins (SonarQube server setting) | SonarQube | `http://sonarqube:9000/sonarqube` |
| Jenkins (Gitea server setting, API only) | Gitea | `http://gitea:3000` |
| SonarQube (webhook) | Jenkins | `http://jenkins:8080/jenkins/sonarqube-webhook/` |
| Gitea (webhook, with `GITEA_WEBHOOK_ALLOWED_HOSTS=jenkins`) | Jenkins | `http://jenkins:8080/jenkins/gitea-webhook/post` |

Two paths go through the public URL and therefore through the certificate:

- Build agents clone repositories. Agents run on the `jenkins-internal` network and reach
  Gitea only through `https://<host>/gitea`, so Git inside the agent must trust the
  certificate. Until that trust is baked into the agent image, use SSH clone URLs in the
  Jenkins Gitea server configuration (checkout credential of type SSH key, port 2222), which
  need no certificate at all.
- Browsers follow redirects between tools during OpenID Connect logins once Keycloak is
  installed; the browser trust above covers it.

If a JVM-based tool must call another through HTTPS anyway, import the certificate into its
truststore. Inside the Jenkins container, for example:

```bash
docker exec -u root jenkins keytool -importcert -noprompt -alias devsecops \
  -file /path/to/server.crt -cacerts -storepass changeit
docker restart jenkins
```

The import lives in the container's filesystem and is lost when the image is rebuilt, which is
why the internal addresses above are the recommended route.

## Using the client's own certificate

When the client has an internal certificate authority, a certificate from it removes every
warning for machines that already trust that CA. Request one for `<host>`, with the IP in the
subject alternative name when `HOST_ADDRESS` is an IP, then:

```bash
sudo cp client.crt /srv/devsecops/traefik/certs/server.crt     # full chain, server first
sudo cp client.key /srv/devsecops/traefik/certs/server.key
sudo chmod 600 /srv/devsecops/traefik/certs/server.key
sudo ./install.sh --only traefik
```

The script reports "using existing certificate" and refreshes the Docker trust copy. The
file must be PEM; if the CA delivered PFX, convert it first with
`openssl pkcs12 -in cert.pfx -out server.crt -clcerts -nokeys` and
`openssl pkcs12 -in cert.pfx -out server.key -nocerts -nodes`.

From then on the certificate's lifetime and renewal are the client's: when the CA reissues
it, copy the new files over the old ones. Traefik reloads them without a restart. The Docker
trust copy must be refreshed as well (`sudo ./install.sh --only traefik` does it).

## Backup

Back up `${DATA_ROOT}/traefik/certs/` with the rest of `DATA_ROOT`. Losing the files is not
a disaster: the next Traefik run generates a new certificate, at the cost of redistributing
it. Losing the client's certificate means asking the CA again.

## Summary

| Question | Answer |
|---|---|
| Who issues it | the installer, self-signed, or the client's CA if files are provided |
| For what name | `HOST_ADDRESS`, IP or DNS name, in the subject alternative name |
| How long | 10 years when generated; the CA's choice otherwise |
| Renews itself | no, and nothing expires before 2036 on a fresh install |
| Regenerate when | `HOST_ADDRESS` changes, key compromise, approaching expiry |
| How | delete the two files, `sudo ./install.sh --only traefik`, redistribute |
| Trusted automatically | the host's Docker daemon and build agents' image pushes |
| Trusted by hand | browsers, Git over HTTPS, other Docker clients, JVM truststores |
