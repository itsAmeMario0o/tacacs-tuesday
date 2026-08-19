# Project status and handoff

Last updated 2026-08-19.

## Where things stand

The lab is up and demo 1's foundation works end to end.

- Azure: `tacacs-tue-rg` in eastus2. VNet, NSGs, Bastion (Standard),
  C8000V at 10.80.0.132, ISE 3.5 at 10.80.0.70. All running. Cost is
  accruing; deallocate or destroy when idle (ADR 0004).
- ISE: deployed 2026-08-17 through the Portal (BYOL 3.5 template,
  `docs/ise-portal-deploy.md`), application up, GUI reachable. The
  August blocker is solved; the fixes were a real NTP server,
  `username=iseadmin` in user_data, and `Etc/UTC`.
- TACACS+: verified 2026-08-18. ISE authenticates `netadmin` to the
  router at privilege 15 with command authorization and accounting.
  Setup and troubleshooting live in `runbook/01-add-router-to-ise.md`.
- SSH keys: Terraform generates per-device pairs into `keys/`
  (ADR 0007), destroyed with the infra. `scripts/20-ssh-c8000v.sh`
  wraps router login.
- Evaluation licensing covers Device Admin, 88 days left as of
  2026-08-18.

## In progress: MCP servers for Claude Desktop

Phase 2. The pamosima/network-mcp-docker-suite runs locally with uv
(not Docker) and talks to Claude Desktop over stdio via an import
shim, since upstream hardcodes HTTP. Both servers pass a stdio
initialize handshake. Setup: `runbook/02-mcp-claude-desktop.md`.
Clone lives at `~/dev/network-mcp-docker-suite`, outside OneDrive so
uv venvs do not churn sync.

## Deferred on purpose

Each of these reverts or bites if forgotten:

- `terraform/variables.tf` `ise_private_ip` default is still 10.80.0.68;
  the live router was hand-corrected to .70. Flip at next full rebuild
  (changing custom_data replaces the VM).
- The router's `ip ssh pubkey-chain` for the repo key was configured
  live, not in the day-0 template. Re-run after any router rebuild
  (see commit 1ef8c66) or fold into the template at next rebuild.
- The ISE VM's Azure-level SSH key is the Portal-generated
  `ise-test-key`, not the repo's `keys/ise_admin` (deploy predates
  ADR 0007). Next ISE rebuild should use the repo key.
- `tfsec` is not installed locally, so that gate has not run.
- OpenAPI on ISE was never confirmed enabled (ERS and pxGrid are).
  Check Administration > System > Settings > API Settings before demo
  tooling that needs it.

## Watch out for

- The `netadmin` password appeared in a terminal screenshot shared in
  a working session. Lab-only account; rotate in ISE if it matters.
- The TACACS+ shared secret decrypts only if pasted exactly; error
  13078 in Live Logs means re-paste it (runbook 01, troubleshooting).
- ISE authorizes local users too once the secret works. `labadmin`
  is permitted in the policy and mirrored as an internal user; do not
  remove either.

## Next

1. Finish Claude Desktop wiring (runbook 02) and verify tools against
   the live devices.
2. Ansible control node and the governed-change path (demo 3).
3. Collection and report scripts (demo 4), then full rehearsal.
