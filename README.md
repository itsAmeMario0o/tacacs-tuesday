# tacacs-tuesday

A small demo lab where an AI assistant helps manage who can log into network
gear, and a human approves every change it makes.

Cisco ISE and a Catalyst 8000V router run in Azure. Claude Desktop talks to
them through the [network-mcp-docker-suite](https://github.com/pamosima/network-mcp-docker-suite)
MCP servers, which run locally with uv and speak stdio (ADR 0008).

## What the demos show

Four short demos, each building on the last:

1. **Discovery:** ask what network devices exist and how they authenticate.
2. **Correlation:** connect a login on the router to the ISE policy that allowed it.
3. **Governed change:** propose a config change, review it, and apply it through Ansible only after a human says yes.
4. **Reporting:** pull the day's activity into a plain summary.

The point is the guardrails. The assistant can read freely, but it cannot
change a live device or write to ISE without a person approving the step.

## How it is built

Two halves.

**Azure**, described entirely in Terraform under `terraform/`. This is the
bulk of the build: a virtual network, two VMs (ISE and the router), network
security groups, and a Bastion host. The VMs have no public IPs. You reach
them through Bastion tunnels from your desktop.

**Your desktop**, for everything else. The MCP servers run locally with uv,
Claude Desktop is the client, Ansible is the change path, and a few scripts
collect data and build reports. None of it needs its own server.

Terraform keeps its state on your local disk because that state holds
secrets. Nothing sensitive is committed. The decision records in
`docs/decisions/` explain the reasoning behind each major choice.

## Repo layout

| Path | What lives here |
|---|---|
| `terraform/` | The Azure build. Local state. |
| `ansible/` | The governed change path: playbooks and inventory. |
| `scripts/` | Numbered bash and Python for setup, collection, and reporting. |
| `config/` | MCP client config example and the router's day-1 config. |
| `runbook/` | Per-demo scripts and the rehearsal checklist. |
| `docs/decisions/` | One short record per architectural choice. |
| `docs/plans/` | Implementation plans. |

## Getting started

You need an Azure subscription, the Azure CLI, Terraform, uv, and Claude
Desktop. The build runs in stages.

Resolve the Cisco marketplace images and stand up the infrastructure:

    scripts/10-resolve-images.sh
    terraform -chdir=terraform init
    terraform -chdir=terraform plan -out=tfplan
    terraform -chdir=terraform apply tfplan

Terraform builds everything except ISE. Deploy ISE by hand from the
Azure Portal, field by field, per `docs/ise-portal-deploy.md` — the
Marketplace image fails Terraform's provisioning timeout, so this step
stays manual (ADR 0006). First boot takes 45 to 60 minutes; watch it
from the Serial Console instead of waiting blind. Then join the router
to ISE over TACACS+ with `runbook/01-add-router-to-ise.md`.

Open Bastion tunnels so your desktop can reach ISE and the router:

    scripts/30-tunnels.sh start

Then wire the MCP servers into Claude Desktop. This takes real work,
because the upstream suite does not speak stdio and Claude Desktop does
not speak anything else for local servers. Four steps, detailed in
`runbook/02-mcp-claude-desktop.md`:

1. **Clone the suite and patch it.** Clone
   pamosima/network-mcp-docker-suite to `~/dev` (outside any synced
   folder). The ios-xe server hardcodes SSH port 22, which macOS will
   not let a tunnel bind, so one line is added to its Netmiko device
   dict to honor an `IOS_XE_PORT` variable:

       "port": int(os.getenv("IOS_XE_PORT", "22")),

2. **Sidestep the hardcoded HTTP transport.** Both servers pin HTTP in
   their `__main__` block. Importing the module instead registers all
   the tools without starting HTTP, and a bare `mcp.run()` then starts
   FastMCP's default transport, which is stdio. That is why the launch
   command below is an import, not a script run. No further upstream
   changes needed.

3. **Create the credential files.** Device credentials live in this
   repo at `config/mcp-env/ios-xe.env` and `config/mcp-env/ise.env`
   (gitignored, mode 600), symlinked into the two server directories,
   which is the only place the servers look for a `.env`.

4. **Edit Claude Desktop's config.** Add two entries under
   `mcpServers` in
   `~/Library/Application Support/Claude/claude_desktop_config.json`
   (full file in `config/claude_desktop_config.example.json`):

       "ios-xe": {
         "command": "uv",
         "args": [
           "run", "--directory",
           "/Users/<you>/dev/network-mcp-docker-suite/ios-xe-mcp-server",
           "python", "-c",
           "from ios_xe_mcp_server import mcp; mcp.run()"
         ]
       },
       "ise": {
         "command": "uv",
         "args": [
           "run", "--directory",
           "/Users/<you>/dev/network-mcp-docker-suite/ise-mcp-server",
           "python", "-c",
           "from ise_mcp_server import mcp; mcp.run()"
         ]
       }

   Quit Claude Desktop fully (Cmd-Q) and reopen. Both servers should
   show running under Settings > Developer, and the tools only work
   while the Bastion tunnels are up.

Before any demo: `scripts/30-tunnels.sh status`, and if anything says
DOWN, `start`. A dead tunnel looks exactly like a broken AI tool.
