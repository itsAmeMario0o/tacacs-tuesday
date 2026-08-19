# 8. Claude Desktop is the MCP client, over stdio

Date: 2026-08-19

## Status

Accepted. Supersedes the client choice implied in the original scope,
which named Claude Code.

## Context

The plan said Claude Code would talk to the MCP suite over HTTP
(`claude mcp add --transport http ...`), with the suite in Docker. When
phase 2 was actually built, the owner called for Claude Desktop as the
client, stdio as the transport, and uv instead of Docker. The demos are
presented from Claude Desktop's chat UI, which is the interface a
customer audience recognizes; a CLI session is the wrong stage prop for
security leadership.

## Decision

Claude Desktop launches both MCP servers locally over stdio, via uv,
from a patched clone of pamosima/network-mcp-docker-suite. The wiring,
including the one-line IOS_XE_PORT patch and the credential layout in
`config/mcp-env/`, is documented in `runbook/02-mcp-claude-desktop.md`.

## Options considered

**Claude Code over HTTP (original plan).** Works, and the suite's HTTP
mode is its native path. Rejected as the demo client because the
audience-facing surface is a terminal, and the HTTP servers would need
the Docker runtime this desktop does not use.

**LibreChat (the suite's own demo client).** Rejected: another service
to run and license-review for a demo that gains nothing from it.

**Claude Desktop over stdio (chosen).** Familiar chat UI on stage, no
extra services, servers spawn on demand. Cost: stdio needs the import
shim and the port patch, both documented and tested.

## Consequences

- README, CLAUDE.md, and the runbooks name Claude Desktop; a future
  swap back to Claude Code is one config-file change, since the servers
  serve either client over stdio.
- The MCP servers only run while Claude Desktop has them open; there is
  no always-on HTTP endpoint, which suits ADR 0004's teardown posture.
- The Bastion tunnels (2222/8443) are a hard runtime dependency for
  every MCP tool call; `scripts/30-tunnels.sh status` is the first
  check when a tool misbehaves.
