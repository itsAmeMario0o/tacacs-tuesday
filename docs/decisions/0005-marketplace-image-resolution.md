# ADR 0005: Resolve marketplace images by script, pin by tfvars

## Status

Accepted, 2026-07-30.

## Context

ISE and the C8000V come from the Azure Marketplace, which needs an exact
publisher, offer, SKU, and version, plus a `plan` block and a one-time
terms acceptance. Marketplace listings churn, values copied from blog
posts go stale, and CLAUDE.md forbids hardcoding them. ADR 0004 adds a
second constraint: every rebuild must land on the identical image, or
the lab quietly changes under us.

## Decision

- `scripts/10-resolve-images.sh` queries `az vm image list` for the
  current ISE and C8000V listings, accepts marketplace terms (safe to
  re-run), and writes the resolved coordinates, version pinned, into a
  gitignored `terraform/images.auto.tfvars`.
- Terraform reads image coordinates only from those variables. No image
  string appears in any `.tf` file.
- Bumping a version means re-running the script on purpose and reviewing
  the change in the plan output.

## Options considered

Hardcode coordinates in `.tf`. Rejected: it breaks a CLAUDE.md "never"
rule, and stale coordinates are the classic marketplace failure.

Use `version = "latest"`. Rejected: two rebuilds a week apart could
deploy different ISE versions in the middle of demo prep.
