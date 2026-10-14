# Semgrep

Pattern-based static analysis with security rule packs for PHP and TypeScript, including
taint tracking from user input to dangerous functions. Complements SonarQube, whose free
edition has no taint analysis.

## Where it runs

Pipeline stage 3, in parallel with the SonarQube scanner. Output is SARIF, archived, uploaded
to DefectDojo, and optionally imported into SonarQube through `sonar.sarifReportPaths`.

## Commands

```bash
semgrep scan --config p/default --config p/php --config p/typescript
semgrep scan --config p/owasp-top-ten --config p/secrets --sarif --output semgrep.sarif
semgrep scan --config rules/ --error        # local rules, non-zero exit on findings
```

`p/...` packs are fetched from the public registry at run time, no account needed. The
Jenkinsfile runs Semgrep with `|| true` at first; switch to `--error --severity ERROR` once
the baseline is clean.

## Configuration

- `.semgrepignore` at the repository root, same syntax as `.gitignore`. Default excludes
  `vendor/`, `node_modules/` and test directories; add generated code.
- Inline: `// nosemgrep: rule-id` on the offending line, with a comment explaining why.
- Custom rules: YAML files in a `rules/` repository owned by the security team, pulled by the
  pipeline. A rule for the client's own unsafe helper takes ten lines.

## Reading results

Findings carry a rule id, severity, a CWE and often a fix suggestion. Taint findings show the
source (a request parameter) and the sink (a query, a shell call, an HTML output). SARIF
viewers in VS Code or the Jenkins Warnings plugin show them inline.

## Free edition and limits

The engine is LGPL and the community rules are free. Semgrep Pro (cross-file taint analysis,
the hosted dashboard, Pro rules) requires an account and a paid plan; nothing here depends on
it. Community rules are single-file, so a taint flow through two files is missed: SonarQube's
paid editions or a manual review cover that gap.
