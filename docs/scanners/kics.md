# KICS

Keeping Infrastructure as Code Secure, Checkmarx's open source IaC scanner. Same role as
Checkov with a different query set; useful as a second opinion or as the primary tool if the
client already uses Checkmarx.

## Where it runs

Not in the example Jenkinsfile. Available in the host wrapper and easy to add as a parallel
step to stage 7. Running both Checkov and KICS doubles the IaC findings to triage, so pick one
per client and keep the other for occasional audits.

## Commands

```bash
kics scan -p deploy
kics scan -p deploy --report-formats json,sarif -o reports
kics scan -p deploy --fail-on high,critical
kics scan -p deploy --exclude-queries <query-id>,<query-id>
```

The host wrapper mounts the current directory at `/src`, so inside the wrapper use
`kics scan -p /src/deploy`.

## Configuration

`kics.config` (JSON or YAML) at the repository root with `exclude-paths`, `exclude-queries`,
`fail-on` and `report-formats`. Inline: `# kics-scan ignore-line` or `ignore-block` comments.
Queries are Rego files under `/app/bin/assets/queries` in the image; custom queries go in a
directory passed with `-q`.

## Platforms covered

Terraform, CloudFormation, Kubernetes, Helm, Docker and Compose, Ansible, OpenAPI, Azure
Resource Manager, Bicep, Pulumi, Google Deployment Manager, Crossplane, GitHub workflows.

## Free edition and limits

Apache 2.0. Checkmarx One is the paid platform; the CLI image is complete. KICS results carry
a Checkmarx severity scale that does not match Checkov's, which is another reason not to mix
both in the same DefectDojo product without a mapping.
