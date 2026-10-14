# Gitleaks

Secret detection in Git repositories: passwords, API keys, private keys and tokens, in the
working tree, the staged changes or the whole history.

## Where it runs

- Developer machine, as the `pre-commit` hook in `templates/pre-commit`, scanning the staged
  diff before each commit. This is the only place a secret can be stopped before it reaches
  the server and its history.
- Pipeline stage 1, `gitleaks detect --source . --redact`, on the full checkout. Fails the build.

## Commands

```bash
gitleaks protect --staged --redact          # pre-commit, staged files only
gitleaks detect --source . --redact         # working tree and history of the clone
gitleaks detect --source . --log-opts="HEAD~20..HEAD"   # only the last 20 commits
gitleaks detect --source . --redact --report-format json --report-path gitleaks.json
```

`--redact` keeps the secret out of the report and the build log. Never remove it in CI.

## Configuration

A `.gitleaks.toml` at the repository root extends the default rules:

```toml
[extend]
useDefault = true

[allowlist]
paths = ['''tests/fixtures/.*''', '''package-lock\.json''']
regexes = ['''EXAMPLE_KEY_[A-Z0-9]+''']

[[rules]]
id = "client-internal-token"
description = "Client internal API token"
regex = '''CLT-[0-9a-f]{32}'''
```

Inline exceptions: append `# gitleaks:allow` to a line. Prefer fixture paths in the allowlist.

## When it fires

A finding in CI means the secret is already in Gitea history. Rotate the secret first, then
remove it from history (`git filter-repo`) only if the repository is small and private; for
anything else, rotation is the fix and the history stays.

## Version and limits

MIT licensed, no paid edition. The pinned image is `GITLEAKS_IMAGE`. Rules match patterns and
entropy, so high-entropy test data produces false positives; that is what the allowlist is for.
