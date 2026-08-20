# Watching the AI work: three visibility layers

Where to look when you want to see, or show, what the AI is doing.
Three layers, each with a different blind spot, which is itself a demo
point: no single tool sees everything, but the network layer catches
every device action regardless of which client made it.

## Layer 1: DefenseClaw (workstation)

Cisco's DefenseClaw runs on this Mac in observe mode, hooked into
Claude Code. Its Mac app is the viewer.

- **Logs > Verdicts tab**: guardrail decisions on Claude Code's tool
  calls as they happen. This is the runtime view.
- **Logs > Stream**: the live firehose. **Gateway** is the daemon's own
  housekeeping, mostly rescan cycles.
- **Audit**: the historical trail (backed by `~/.defenseclaw/audit.db`).
- **Alerts**: scanner findings plus runtime matches. The search box is
  plain text over the visible columns; use the Kind dropdown to
  separate categories. (The `connector:` token syntax belongs to the
  terminal TUI, `defenseclaw tui`, not the Mac app.)

The hard limit: **DefenseClaw does not see Claude Desktop.** Desktop is
not a supported connector (the capability matrix lists hook-based
connectors like Claude Code, Codex, and Cursor; Desktop has no hook
system to attach to). AI Discovery inventories Desktop and its MCP
servers but records no runtime traffic. Do not burn time trying to
make it appear; the layers below cover Desktop.

Known noise, left alone deliberately: the skill scanner logs
`SKILL.md not found in ~/.claude/skills/learned` every rescan cycle
because that directory exists empty. Harmless; filter around it.

### The live event stream

DefenseClaw also writes every event to a local JSONL file (configured
2026-08-20 in `~/.defenseclaw/config.yaml`, destination `local-events`):

    tail -f ~/.defenseclaw/events.jsonl

Each line carries connector, bucket, severity, action, and correlation
IDs. The buckets worth watching: `tool.activity` (every Claude Code
tool call), `guardrail.evaluation` (every judgment on one), and
`security.finding`. Paths in that config must be absolute; the daemon
does not expand `~`. Enforcement stays in observe mode on purpose;
this layer narrates, it does not block.

## Layer 2: Claude Desktop's own MCP logs

Desktop writes one log per MCP server, per tool call, including
connection details and results:

    tail -f ~/Library/Logs/Claude/mcp-server-ios-xe.log \
            ~/Library/Logs/Claude/mcp-server-ise.log

This is the live feed of Desktop's MCP traffic. It is also the first
place to look when a Desktop tool call fails; the Python traceback
lands here.

## Layer 3: ISE TACACS Live Log (network)

Work Centers > Device Administration > Overview > TACACS Live Log.
Every router command from either client authenticates and accounts as
`netadmin` through TACACS+, so this layer sees all AI device activity
no matter which client, which machine, or which tool produced it.

## The demo shot

Split screen: ISE Live Log on one side, DefenseClaw's Verdicts (for
Claude Code) or the tailed MCP logs (for Claude Desktop) on the other,
while the AI runs a discovery prompt. One prompt, two independent
audit trails, neither of which the AI can opt out of.
