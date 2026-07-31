# tacacs-tuesday

Demo lab. Cisco ISE and Catalyst 8000V running in Azure, driven by the
`pamosima/network-mcp-docker-suite` MCP servers through Claude Code.

Four demos: discovery, correlation, governed change, reporting.
Audience is financial services engineering and security leadership.

Not a product. Not production. Optimize for demo reliability and honest
claims over completeness. A confident wrong statement in front of a
customer costs more than an admitted gap.

## Scope

In scope: ISE TACACS+ device administration only. Catalyst 8000V as the
network access device. Ansible as the governed change path. Claude Code as
the MCP client.

Out of scope: 802.1X, MAB, profiling, RADIUS of any kind, Catalyst switches
(no virtual Cat9k exists), GitLab CE, AWX, Kubernetes.

Do not add out-of-scope components. If a task seems to need one, stop and ask.

## Where work happens

Two halves, unequal.

**Azure, via Terraform.** The bulk of the build. Two VMs, a VNet, NSGs,
Bastion. This is where the effort and the risk are. Marketplace images, plan
blocks, user data, day-0 config.

**Local desktop.** Everything else. Docker running the MCP suite, Claude Code
as the client, the Ansible control node, the collection and report scripts,
the runbooks. None of it needs a server. Reach Azure through Bastion tunnels.

Default to local. Before adding an Azure resource, ask whether it could run on
the desktop instead. The answer is usually yes, and it is cheaper and faster
to iterate.

## Repo layout

| Path | Contents |
|---|---|
| `terraform/` | Azure IaC. Local state. The bulk of the work. |
| `terraform/modules/{foundation,ise,c8000v,bastion}/` | One module per component |
| `ansible/` | `ansible.cfg`, `requirements.yml` |
| `ansible/inventory/` | Hosts and vault-encrypted group_vars |
| `ansible/playbooks/` | `01-facts` through `05-rollback` |
| `scripts/` | Numbered bash and Python, `00-` through `99-` |
| `config/` | MCP client config example, `router-day1.cfg` |
| `runbook/` | Per-demo scripts and the rehearsal checklist |
| `docs/decisions/` | ADRs. One file per architectural choice. |

## Commands

<!-- TODO: confirm all of these against the built environment before trusting them -->

    # Tunnels (each occupies a terminal)
    az network bastion tunnel -n bas-lab -g $RG --target-resource-id $ISE_ID  --resource-port 443 --port 8443
    az network bastion tunnel -n bas-lab -g $RG --target-resource-id $C8KV_ID --resource-port 22  --port 2222

    # MCP servers
    docker compose --profile cisco up -d
    claude mcp add --transport http ios-xe http://localhost:8003/mcp
    claude mcp add --transport http ise    http://localhost:8005/mcp
    claude mcp list

    # Terraform
    terraform -chdir=terraform init
    terraform -chdir=terraform validate
    terraform -chdir=terraform plan -out=tfplan

    # Ansible
    source .venv/bin/activate
    ansible-playbook playbooks/01-facts.yml --syntax-check
    ansible-playbook playbooks/03-apply-change.yml --check --diff

    # Quality
    pre-commit run --all-files

## Human approval required

STOP and ask. Do not proceed on inference.

- `terraform apply`, `terraform destroy`, any `terraform state` subcommand
- Any write to a live device: `config_command`, or `ansible-playbook` without `--check`
- Any write to ISE
- Installing or upgrading a dependency, collection, or provider
- Git history rewrite: `reset --hard`, `checkout .`, `clean -f`, `push --force`,
  `push -f`, `rebase`, `commit --amend` on a pushed commit
- Editing `CLAUDE.md`, `.claude/`, `.gitignore`, `.pre-commit-config.yaml`, `.gitleaks.toml`
- Creating a file outside the paths in Repo layout
- Modifying or deleting an existing file. State the file, the lines, and the change first.

## Never

- **Never commit `terraform.tfstate`.** State is local and holds the ISE admin
  password, the TACACS+ shared secret, and device credentials in plaintext.
  `*.tfstate*` is gitignored. Do not remove it.
- **Never hardcode a marketplace publisher, offer, SKU, or version.** Resolve
  with `az vm image list`, then pin the version explicitly. Values copied from
  blog posts or documentation go stale.
- **Never remove the `local` fallback from an AAA line.** Lockout on an Azure
  VM with no console means rebuild.
- Never write a secret, key, token, subscription ID, or tenant ID into any file.
- Never ask me to paste a secret into chat.

## Skills

Load the matching `SKILL.md` before writing. Name the skill you used and why.

| Task | Skills |
|---|---|
| Terraform in `terraform/` | `terraform-patterns`, `azure-cloud-architect`, `cloud-security`, `senior-secops` |
| Ansible, device config, scripts | `senior-secops`, `senior-backend` for non-trivial Python |
| Azure Key Vault, secret handling | `secrets-vault-manager` |
| Docker Compose for the MCP suite | `docker-development` |
| Debugging anything broken | `focused-fix`. Do not blind-patch. |
| Reviewing changes | `code-reviewer`, plus `senior-security` for anything touching credentials |
| Runbooks, talk tracks, customer prose | `humanizer`, `written-communication`, `professional-proofreader` |
| Demo narrative and sequencing | `storytelling`, `presentation-skills` |
| Reviewing a plan or architecture I present | `grill-me` |

Architectural decisions get an ADR in `docs/decisions/` before implementation.
One file, one decision, with the options considered and why the loser lost.

If no skill maps cleanly, say so and ask before proceeding freeform.

## Code style

Keep it simple. Prioritize readability and understandability above all. A
college freshman in computer science should be able to follow the basics.

- No clever tricks. No premature abstraction. No deeply nested logic.
- Functions under 40 lines. Nesting under 3 levels.
- Descriptive names. No single letters outside loop counters.
- Comments explain why, not what.
- Two call sites before you extract a helper or a module.
- Bash: `set -euo pipefail`. Quote every variable. No unguarded `rm`.
- Python: type hints on every signature. Standard library first. `ruff` and `black` clean.
- Terraform: no magic strings. Every variable has a description and a type.
  Tag every resource with `owner` and `expires`.

## Testing

There is no unit test suite. The gates are:

- `terraform fmt -check`, `terraform validate`, `tfsec` on every `.tf` change
- `ansible-playbook --syntax-check` on every playbook change
- `ansible-playbook --check --diff` before any apply
- `pytest` for `scripts/40-collect.py` and `scripts/41-report.py` once they hold logic
- A full rehearsal from clean `terraform apply` to demo 4 before any customer session

Idempotency counts as a test. Every playbook runs twice with `changed=0` on the second pass.

## Definition of done

1. Skill consulted and named in the response
2. ADR written, for architectural changes
3. Relevant gate passed: `validate` + `tfsec`, or `--syntax-check` + `--check`
4. `pre-commit run --all-files` passes
5. One logical commit, descriptive message
6. Changed files and their purpose summarized
