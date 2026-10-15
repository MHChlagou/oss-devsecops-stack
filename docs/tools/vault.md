# Vault

Secrets store. Pipelines fetch registry passwords, API tokens and deployment keys from Vault at
run time instead of keeping them in Jenkins credentials or in Git.

## Role in the chain

Jenkins credentials are convenient but live in `jenkins_home`, are readable by any pipeline
on the controller, and have no audit trail. Vault gives short-lived access through AppRole,
records every read, and is the single place to rotate a secret. Application containers can
also read their configuration from it at startup.

## Deployment

| Item | Value |
|---|---|
| Stack | `stacks/vault/docker-compose.yml`, installed by `scripts/25-vault.sh` |
| Image | `VAULT_IMAGE` |
| Config | `${DATA_ROOT}/vault/config/vault.hcl`, file storage backend, TLS terminated by Traefik |
| Data | `${DATA_ROOT}/vault/file` |
| URL | `https://<host>:8200/ui/` |
| Budget | 0.2 vCPU, 256 MB |

The container has `IPC_LOCK` so Vault can keep its memory out of swap. Single node, file
storage: enough for a platform of this size, no high availability.

## Initialisation and unseal

The installer does not initialise Vault. Run once, from a terminal only trusted people see:

```bash
docker exec -it vault vault operator init -key-shares=5 -key-threshold=3
```

Vault prints five unseal keys and a root token exactly once. Give each key to a different
person or store them in the client's password manager as separate entries. The root token is
for the first setup only; revoke it after creating admin policies.

After every restart Vault is sealed. Three key holders run:

```bash
docker exec -it vault vault operator unseal
```

Auto-unseal needs a cloud KMS or a second Vault, so it is out of scope for a zero-cost
private setup. Document the unseal procedure in the client's runbook and test it quarterly.

## Setup for the pipeline

```bash
docker exec -it vault sh
vault login            # root token, once
vault secrets enable -path=secret kv-v2
vault auth enable approle
vault policy write jenkins-ci - <<'POLICY'
path "secret/data/ci/*"     { capabilities = ["read"] }
path "secret/metadata/ci/*" { capabilities = ["list"] }
POLICY
vault write auth/approle/role/jenkins token_policies=jenkins-ci token_ttl=1h secret_id_ttl=0
vault read auth/approle/role/jenkins/role-id
vault write -f auth/approle/role/jenkins/secret-id
```

Store the role id and secret id in Jenkins as a "Vault AppRole Credential" (from the
`hashicorp-vault-plugin`, already installed) and configure the Vault URL under Manage Jenkins,
System, Vault. In a pipeline:

```groovy
withVault(vaultSecrets: [[path: 'secret/ci/nexus', secretValues: [[envVar: 'REG_PASS', vaultKey: 'password']]]]) {
  sh 'echo "$REG_PASS" | docker login $REGISTRY -u ci --password-stdin'
}
```

Put the Nexus registry account, the SonarQube token, the DefectDojo and Dependency-Track API
keys and deployment SSH keys under `secret/ci/`. The example Jenkinsfile uses Jenkins
credentials for simplicity; migrate them to `withVault` once Vault is unsealed and policies exist.

## Operations

- Backup: stop writes and copy `${DATA_ROOT}/vault/file`, or use `vault operator raft snapshot`
  if you move to the Raft backend later. Backups are encrypted with the unseal keys, so a backup
  without the keys is useless and a backup with the keys is a full compromise. Store them apart.
- Audit log: `vault audit enable file file_path=/vault/logs/audit.log`. Ship it to Loki by
  adding the path to Promtail.
- Upgrade: bump `VAULT_IMAGE`, restart, unseal. Read the upgrade notes for each minor version.
- The UI at `/ui/` is the quickest way to inspect policies and leases.

## Free edition notes

Vault Community is free of charge under the Business Source License, which forbids offering it
as a competing hosted service and nothing else relevant here. OpenBao is the MPL-licensed fork
with the same CLI and API; swap `VAULT_IMAGE` for `openbao/openbao` and the stack works unchanged
if the client requires an OSI licence.
