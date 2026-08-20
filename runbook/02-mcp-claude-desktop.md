# MCP servers for Claude Desktop

Wire the ios-xe and ise MCP servers from pamosima/network-mcp-docker-suite
into Claude Desktop, running locally with uv and talking stdio. Verified
end to end on 2026-08-19: a tools/call over stdio returned `show clock`
from the router through the Bastion tunnel, authenticated by TACACS+.

Three departures from the suite's own docs, all deliberate:

- **uv instead of Docker.** The servers are plain FastMCP Python apps;
  `uv run` in each server directory resolves and caches the deps. No
  containers, and the servers reach the Bastion tunnels on localhost.
- **stdio instead of HTTP.** Upstream hardcodes HTTP in `__main__`.
  Importing the module registers the tools without starting HTTP, and a
  bare `mcp.run()` starts FastMCP's default transport, which is stdio:
  `python -c "from ios_xe_mcp_server import mcp; mcp.run()"`.
- **One local patch.** The ios-xe server hardcodes SSH port 22, and
  macOS refuses to let the tunnel bind local port 22 (low ports are
  privileged; tested, `Permission denied`). The clone carries a one-line
  patch adding a `"port"` key from `IOS_XE_PORT` to the Netmiko dict in
  `create_safe_device_dict`. Visible with `git diff` in the clone; worth
  offering upstream as a PR. The ise server needs no patch because its
  URL builder accepts `ISE_HOST=127.0.0.1:8443`.

Claude Desktop is the MCP client of record (ADR 0008). The same servers
would serve Claude Code equally well over stdio if that ever changes.

## Layout

| Piece | Where | Why |
|---|---|---|
| Suite clone (+ patch) | `~/dev/network-mcp-docker-suite` | Outside OneDrive so uv venvs do not churn sync |
| Credentials | `config/mcp-env/*.env` in this repo | Part of the project; directory self-gitignored |
| Symlinks | each server dir's `.env` → the repo file | The servers only read `.env` from their own cwd |
| Client config | `~/Library/Application Support/Claude/claude_desktop_config.json` | Where Claude Desktop requires it; holds no secrets |

## 1. Clone, patch, prewarm

    mkdir -p ~/dev && cd ~/dev
    git clone https://github.com/pamosima/network-mcp-docker-suite.git

Apply the port patch to
`ios-xe-mcp-server/ios_xe_mcp_server.py`, inside `create_safe_device_dict`:

    "host": host,
    "port": int(os.getenv("IOS_XE_PORT", "22")),   # added line

Prewarm each server once so Claude Desktop's first launch is not a
dependency install:

    cd ~/dev/network-mcp-docker-suite
    uv run --directory ios-xe-mcp-server python -c "import ios_xe_mcp_server"
    uv run --directory ise-mcp-server python -c "import ise_mcp_server"

## 2. Credentials

The real files live in this repo at `config/mcp-env/`, mode 600, with a
local `.gitignore` that keeps everything but itself out of git. Contents:

`config/mcp-env/ios-xe.env`

    IOS_XE_USERNAME=netadmin
    IOS_XE_PASSWORD=<the netadmin password set in ISE>
    IOS_XE_READ_ONLY=true
    IOS_XE_PORT=2222

`config/mcp-env/ise.env`

    ISE_HOST=127.0.0.1:8443
    ISE_USERNAME=iseadmin
    ISE_PASSWORD=<the CURRENT iseadmin GUI password — see below>
    ISE_VERIFY_SSL=False

The ISE password is NOT the Terraform output. ISE forces a password
change at first GUI login, which orphans the day-0 password the moment
a human signs in. Whatever you log into the GUI with today is what
goes here.

Symlink them to where the servers look:

    ln -sf "<repo>/config/mcp-env/ios-xe.env" ~/dev/network-mcp-docker-suite/ios-xe-mcp-server/.env
    ln -sf "<repo>/config/mcp-env/ise.env"    ~/dev/network-mcp-docker-suite/ise-mcp-server/.env

Why these values:

- **`netadmin`, not `labadmin`:** every command the AI runs flows through
  TACACS+ and lands in the ISE Live Log. The AI's device access being
  visible in the audit trail is the demo.
- **`IOS_XE_READ_ONLY=true`:** MCP is the discovery and correlation path
  (demos 1 and 2). Writes go through governed Ansible (demo 3).
- **`127.0.0.1` with high ports:** the standard Bastion tunnels from
  `00-device-access.md` (2222 for router SSH, 8443 for ISE HTTPS). Do
  not try to tunnel on local 22 or 443; macOS denies the bind.

## 3. Tunnels

The same two tunnels as `00-device-access.md`, both up whenever Claude
Desktop uses the tools. The router's address, as far as Claude is
concerned, is `127.0.0.1`.

## 4. Claude Desktop config

`~/Library/Application Support/Claude/claude_desktop_config.json`, two
entries under `mcpServers` (full example in
`config/claude_desktop_config.example.json`):

    "ios-xe": {
      "command": "uv",
      "args": [
        "run", "--directory",
        "/Users/mariorui/dev/network-mcp-docker-suite/ios-xe-mcp-server",
        "python", "-c",
        "from ios_xe_mcp_server import mcp; mcp.run()"
      ]
    },
    "ise": { same shape, ise-mcp-server and ise_mcp_server }

Paths are absolute because Claude Desktop launches servers with no
useful working directory. After editing, fully quit Claude Desktop
(Cmd-Q) and reopen.

## 5. Verify

1. Settings > Developer: both servers show running.
2. "Using the ise tools, list the network devices in ISE." Expected:
   `c8kv-lab`, 10.80.0.132.
3. "Using the ios-xe tools, run 'show ip interface brief' on
   127.0.0.1." Expected: the router's interface table.
4. Open the ISE TACACS Live Log: the AI's session from step 3 is there,
   authenticated as `netadmin`, every command accounted. Demo 2's
   opening beat.

## Troubleshooting

- **Server shows "failed" in Desktop:** run the config's exact command
  in a terminal; the import error is plain. Usually the `.env` symlink
  is missing or the repo file moved.
- **`Missing required environment credentials` in the log:** same
  cause; the server directory has no working `.env`.
- **ios-xe tool times out:** the 2222 tunnel is down.
- **ise tool 401:** wrong password in `ise.env`. First place to look:
  ISE forced a password change at first GUI login, so the Terraform
  password is stale from that moment on. Put the current GUI password
  in `ise.env`, then fully restart Claude Desktop; the server only
  reads `.env` at launch. Confirm ERS (Read/Write) is toggled on under
  Administration > System > Settings > API Settings while you are
  there. (Both bit us on 2026-08-19.)
- **ise tool connection error with the tunnel up:** ERS not answering;
  check ISE > Administration > Settings > API Settings.
