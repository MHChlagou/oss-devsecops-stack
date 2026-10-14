# OWASP ZAP

Dynamic application security testing. Crawls and attacks the running application on staging
and reports what an attacker sees from outside: missing headers, injection points, outdated
components, authentication weaknesses.

## Where it runs

Pipeline stage 9, after the deployment to staging, with the baseline scan. Report-only in the
example Jenkinsfile because dynamic findings need a human look before they block anything.
A full scan runs on a schedule (nightly or weekly), not per commit, because it takes an hour
and generates load.

## Commands

The image ships helper scripts. Through the host wrapper, the current directory is `/zap/wrk`,
where reports are written.

```bash
zap zap-baseline.py -t https://staging.<client> -r baseline.html -J baseline.json
zap zap-baseline.py -t https://staging.<client> -c baseline.conf -m 10      # 10 minutes of spidering
zap zap-full-scan.py -t https://staging.<client> -r full.html -J full.json  # active attacks, slow
zap zap-api-scan.py -t https://staging.<client>/openapi.json -f openapi -r api.html
```

Baseline: passive scan of what the spider finds, safe to run against any environment, a few
minutes. Full: active scan with payloads, staging only, never production, and never an
environment that sends real emails or payments.

## Configuration

- `baseline.conf` (generated with `-g baseline.conf` on the first run) lists every rule with
  `WARN`, `FAIL` or `IGNORE`. Promote rules to `FAIL` one at a time as they are fixed.
- Authentication: an automation framework plan (`-autorun plan.yaml`) handles form or OIDC
  login, scoped contexts and users. Required for anything behind Keycloak.
- Scope: always set the target to the staging hostname only, and tell the client's operations
  team before the first full scan so the traffic is not mistaken for an attack.

## Reading results

Alerts have a risk (High to Informational) and a confidence. Start with high risk, high
confidence. Missing security headers and cookie flags are the usual first batch and are fixed
at the reverse proxy or framework level. Injection alerts need reproduction before being
filed as bugs.

## Free edition and limits

Apache 2.0, a Software Security Project under the Linux Foundation after leaving OWASP's
umbrella in 2024, still called OWASP ZAP in most places. No paid edition. It does not
understand single-page applications without the AJAX spider (`-j` flag) and needs an
authenticated plan to see anything behind a login.
