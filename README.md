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

Open Bastion tunnels so your desktop can reach ISE and the router:

    scripts/30-tunnels.sh start

Wire the MCP servers into Claude Desktop. The walkthrough is
`runbook/02-mcp-claude-desktop.md`; the short version is a uv-managed
clone of the suite, credentials in `config/mcp-env/`, and two stdio
entries in Claude Desktop's config (example in
`config/claude_desktop_config.example.json`).

Cisco ISE takes about half an hour to finish booting the first time. Give it
that before you expect the admin console to answer.
