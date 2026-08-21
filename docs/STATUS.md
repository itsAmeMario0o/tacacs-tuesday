# Project status and handoff

Last updated 2026-08-21.

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

## Done: MCP servers for Claude Desktop

Phase 2, confirmed working in Claude Desktop on 2026-08-19. The
pamosima/network-mcp-docker-suite runs locally with uv (not Docker)
and talks stdio via an import shim, since upstream hardcodes HTTP.
The ios-xe clone carries a one-line IOS_XE_PORT patch; credentials
live in `config/mcp-env/` (self-gitignored) symlinked into the server
directories. Setup and troubleshooting:
`runbook/02-mcp-claude-desktop.md`. The Bastion tunnels (2222 router,
8443 ISE) must be up for the tools to work; a dead tunnel presents as
a broken tool.

## Done: MCP verified in Claude Desktop, both devices answering

Confirmed working 2026-08-20 through the real client: ISE device list
and router show commands both return through the MCP servers. Tested
at the protocol level too (stdio tools/call). One capability finding:
the ise MCP server is read-only by construction (21 GET tools, no
POST, no version tool), and the ios-xe server runs with
IOS_XE_READ_ONLY=true. Writes stay with the governed Ansible path by
design; see the demo-3 framing in the runbooks.

## Done: DefenseClaw visibility, no enforcement

Cisco DefenseClaw runs on this Mac, hooked into Claude Code, observe
mode with fail-open (deliberate; do not flip to action without a
decision). Configured 2026-08-20: a local JSONL event stream at
~/.defenseclaw/events.jsonl (absolute paths only; the daemon does not
expand ~; config backup at config.yaml.bak-2026-08-20).

- Viewers: the DefenseClaw Mac app (Logs > Verdicts for runtime),
  `defenseclaw tui`, and `scripts/50-ai-event-feed.sh` for the live
  terminal feed.
- The three-layer visibility model and the rehearsed four-shot demo
  arc live in `runbook/03-ai-activity-visibility.md`. Key limit:
  DefenseClaw cannot see Claude Desktop (not a supported connector);
  Desktop is covered by its own MCP logs and the ISE Live Log.
- Galileo (cloud trace dashboards) was evaluated and shelved: it
  exports prompt and tool content off-box, which cuts against the
  on-box governance story. Name-drop it in the talk track instead.

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

- The iseadmin GUI/API password is NOT the Terraform output anymore:
  ISE forces a change at first GUI login. The current password lives
  only in `config/mcp-env/ise.env` (and the owner's head). The
  `ise_admin_password` output still matters for a fresh ISE deploy,
  but stops being true the moment someone logs in.

- The `netadmin` password appeared in a terminal screenshot shared in
  a working session. Lab-only account; rotate in ISE if it matters.
- The TACACS+ shared secret decrypts only if pasted exactly; error
  13078 in Live Logs means re-paste it (runbook 01, troubleshooting).
- ISE authorizes local users too once the secret works. `labadmin`
  is permitted in the policy and mirrored as an internal user; do not
  remove either.

## Next

1. Ansible control node and the governed-change path (demo 3). The
   biggest unbuilt piece; the AI-drafts-values-into-reviewed-playbooks
   pattern is the agreed design.
2. Collection and report scripts (demo 4). The ISE MnT API and the
   DefenseClaw JSONL stream are the two data sources.
3. Per-demo talk tracks and the rehearsal checklist, then a full
   rehearsal. Demos 1 and 2 are functional today; the owner has run
   them and called the talking points solid.

Session-start ritual: `scripts/30-tunnels.sh status` (start if DOWN),
then `scripts/50-ai-event-feed.sh` in a spare terminal if DefenseClaw
visibility is part of the session.
