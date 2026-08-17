# 7. Terraform generates and stores device SSH keys in keys/

Date: 2026-08-17

## Status

Accepted

## Context

Device logins were inconsistent. The router used password auth only. The
ISE deploy script called `az vm create --generate-ssh-keys`, which drops
keys in `~/.ssh` outside the repo. The Portal deploy generated a third
key through Azure that lives wherever the browser downloaded it. Three
paths, three key locations, none tracked by the tooling that builds the
lab.

CLAUDE.md says never write a key into any file. That rule exists for
secrets that leak through git. The owner explicitly overrode it for this
case: this is a lab, the keys grant access to two throwaway VMs reachable
only through Bastion, and the Terraform state in the same directory
already holds every password in plaintext.

## Decision

Root Terraform generates one RSA 4096 keypair per device (`tls_private_key`)
and writes both halves to a `keys/` directory at the repo root
(`local_sensitive_file`, mode 0600 for private halves). `keys/.gitignore`
ignores everything except itself, so nothing under it can be committed.

Everything that logs in references these files: the c8000v VM gets the
public key as an `admin_ssh_key`, and `scripts/90-ise-deploy.sh` passes
`keys/ise_admin.pub` instead of `--generate-ssh-keys`. Portal deploys
paste the same public key.

Because the files are Terraform resources, `terraform destroy` deletes
them with the infrastructure. A rebuild mints fresh keys. No key outlives
the VMs it opens.

Password auth on the router stays enabled and the AAA `local` fallback
stays in place; the key is an addition, not a replacement.

## Options considered

**Keys in ~/.ssh via --generate-ssh-keys (status quo).** Rejected: keys
survive `terraform destroy`, accumulate across rebuilds, and live outside
the repo where nothing manages them.

**Azure Key Vault.** Rejected: an extra Azure resource and an extra
dependency for a lab that optimizes for cheap teardown (ADR 0004). Vault
soft-delete also makes true destroy slower, not faster.

**No SSH keys, passwords only.** Rejected: the ISE image installs a key
for the Linux user by design, and Cisco's own automation uses key auth.
Fighting the platform costs more than following it.

## Consequences

- Adds the `hashicorp/local` provider.
- Adding `admin_ssh_key` to the c8000v VM is a create-time change, so the
  running router is replaced once when this lands.
- The dormant ISE module still generates its own key internally. When ISE
  returns to Terraform (if ever), fold it into the root keypair.
- Private keys sit unencrypted in `keys/` and in local state. Acceptable
  for this lab, wrong anywhere else.
