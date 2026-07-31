# ADR 0004: Destroy the lab between work sessions

## Status

Accepted, 2026-07-30.

## Context

Left running, the lab costs $400 or more a month for the ISE VM, Bastion
Standard, and disks. While it is up, it costs about $0.75 an hour. ISE
needs 30 to 45 minutes to boot and stabilize from any cold start,
whether that start is a VM start or a fresh apply.

## Decision

Run `terraform destroy` at the end of each work session and
`terraform apply` before the next. A `scripts/99-destroy.sh` wrapper
makes teardown a one-liner, still human approved. The `expires` tag on
every resource is the cleanup backstop.

## Consequences

This only works if rebuild is fully automated, so it forces:

- Complete day-0 config in Terraform user data: ISE identity and network
  bootstrap, C8000V AAA with the `local` fallback.
- ISE application config (the network device entry, shell profiles,
  command sets, and policy sets) rebuilt by a script or playbook against
  the ISE API after every apply. This is a required deliverable.
- Pinned marketplace image versions (ADR 0005) so every rebuild produces
  the same lab.

There is an upside: every rebuild rehearses the recovery path, which
suits a demo that sells reproducibility.

## Options considered

Deallocate nightly and keep state. Rejected: disks and Bastion keep
billing, ISE still needs its long stabilization after every start, and
config drift builds up between demos.

Leave it running until the demo wraps. Rejected: the most expensive
option, and it lets the rebuild path rot unexercised until the worst
possible moment.
