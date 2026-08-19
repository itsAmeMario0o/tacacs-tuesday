# MCP servers for Claude Desktop

Wire the ios-xe and ise MCP servers from pamosima/network-mcp-docker-suite
into Claude Desktop, running locally with uv and talking stdio.

Two departures from the suite's own docs, both deliberate:

- **uv instead of Docker.** The servers are plain FastMCP Python apps;
  `uv run` in each server directory resolves and caches the deps. No
  containers, and the servers can reach the Bastion tunnels on
  localhost directly.
- **stdio instead of HTTP.** Upstream hardcodes HTTP in `__main__`
  (`mcp.run(transport="streamable-http", ...)`). Importing the module
  instead of executing it registers all the tools without starting
  HTTP, and a bare `mcp.run()` starts FastMCP's default transport,
  which is stdio: `python -c "from ios_xe_mcp_server import mcp;
  mcp.run()"`. Verified with an initialize handshake on 2026-08-19.
  No upstream code is modified.

Note the scope wrinkle: CLAUDE.md names Claude Code as the MCP client;
this runbook wires Claude Desktop by explicit request. The same servers
serve either client.

## 1. Clone and prewarm

    mkdir -p ~/dev && cd ~/dev
    git clone https://github.com/pamosima/network-mcp-docker-suite.git

The clone lives outside OneDrive on purpose: uv creates `.venv`
directories that OneDrive would sync forever.

Prewarm each server once so Claude Desktop's first launch is not a
90-second dependency install:

    cd ~/dev/network-mcp-docker-suite
    uv run --directory ios-xe-mcp-server python -c "import ios_xe_mcp_server" 2>/dev/null
    uv run --directory ise-mcp-server python -c "import ise_mcp_server" 2>/dev/null

(Import warnings about missing env vars are fine here.)

## 2. Credentials via .env files

Each server reads a `.env` from its own directory. Secrets stay in
these two files, not in the Claude Desktop config. Create them
yourself from the repo root (nothing prints):

    cd <tacacs-tuesday repo root>

    cat > ~/dev/network-mcp-docker-suite/ios-xe-mcp-server/.env <<EOF
    IOS_XE_USERNAME=netadmin
    IOS_XE_PASSWORD=<the netadmin password you set in ISE>
    IOS_XE_READ_ONLY=true
    EOF

    cat > ~/dev/network-mcp-docker-suite/ise-mcp-server/.env <<EOF
    ISE_HOST=127.0.0.1
    ISE_USERNAME=iseadmin
    ISE_PASSWORD=$(terraform -chdir=terraform output -raw ise_admin_password)
    ISE_VERIFY_SSL=False
    EOF

Why these values:

- **`netadmin`, not `labadmin`:** every command the AI runs then flows
  through TACACS+ and lands in the ISE Live Log. The AI's device access
  being visible in the audit trail is the demo.
- **`IOS_XE_READ_ONLY=true`:** the MCP path is for discovery and
  correlation (demos 1 and 2). Writes go through the governed Ansible
  path (demo 3). Flip to false only if a demo explicitly needs it.
- **`ISE_HOST=127.0.0.1`:** the server reaches ISE through the Bastion
  tunnel on local port 443 (next section). SSL verification off because
  ISE presents a self-signed cert for an IP.

## 3. Tunnels on the real ports

The ios-xe server SSHes to whatever host Claude names, always on port
22 (hardcoded in its Netmiko dict). The ise server calls
`https://ISE_HOST` on 443. So the MCP tunnels bind the real ports
locally; macOS allows low ports without root:

    # Terminal 1: router SSH on local 22
    az network bastion tunnel -n bas-lab -g tacacs-tue-rg \
      --target-resource-id "$(az vm show -g tacacs-tue-rg -n c8kv-lab --query id -o tsv)" \
      --resource-port 22 --port 22

    # Terminal 2: ISE API and GUI on local 443
    az network bastion tunnel -n bas-lab -g tacacs-tue-rg \
      --target-resource-id "$(az vm show -g tacacs-tue-rg -n ise-test --query id -o tsv)" \
      --resource-port 443 --port 443

Both tunnels must be up whenever Claude Desktop uses the tools. The
router's address, as far as Claude is concerned, is `127.0.0.1`. Side
benefit: with these two tunnels, the ISE GUI is just
`https://127.0.0.1` and router SSH needs no `-p` (use
`TUNNEL_PORT=22 scripts/20-ssh-c8000v.sh`).

If port 22 refuses to bind, something local is listening; `lsof -nP
-i :22` will name it (macOS Remote Login is the usual suspect).

## 4. Claude Desktop config

Config file: `~/Library/Application Support/Claude/claude_desktop_config.json`.
A ready example is in `config/claude_desktop_config.example.json`; the
two entries to merge under `mcpServers`:

    "ios-xe": {
      "command": "uv",
      "args": [
        "run", "--directory",
        "/Users/mariorui/dev/network-mcp-docker-suite/ios-xe-mcp-server",
        "python", "-c",
        "from ios_xe_mcp_server import mcp; mcp.run()"
      ]
    },
    "ise": {
      "command": "uv",
      "args": [
        "run", "--directory",
        "/Users/mariorui/dev/network-mcp-docker-suite/ise-mcp-server",
        "python", "-c",
        "from ise_mcp_server import mcp; mcp.run()"
      ]
    }

Paths are absolute because Claude Desktop launches servers with no
useful working directory. Fully quit Claude Desktop (Cmd-Q, not just
the window) and reopen after editing.

## 5. Verify

1. Claude Desktop > Settings > Developer: both servers show running,
   no red state.
2. Ask Claude: "Using the ise tools, list the network devices in ISE."
   Expected: one device, `c8kv-lab`, 10.80.0.132.
3. Ask Claude: "Using the ios-xe tools, run 'show ip interface brief'
   on 127.0.0.1." Expected: interface table from `c8kv-lab`.
4. The kicker: open the ISE TACACS Live Log. The AI's session from
   step 3 is there, authenticated as `netadmin`, every command
   accounted. That is demo 2's opening beat.

## Troubleshooting

- **Server shows "failed" in Desktop:** run the exact command from the
  config in a terminal; the import error will be plain (usually a
  missing `.env` in the server directory).
- **ios-xe tool times out:** the port-22 tunnel is down, or something
  else grabbed the port.
- **ise tool returns 401:** wrong password in the ise `.env`.
- **ise tool returns connection errors with the tunnel up:** ERS API
  not answering; check ISE > Administration > Settings > API Settings
  (ERS was enabled in day-0, but verify after any ISE change).
