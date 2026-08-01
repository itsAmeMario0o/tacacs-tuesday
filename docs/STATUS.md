# Project status and handoff

Last updated 2026-07-31.

## Where things stand

The Azure infrastructure is built and correct. Terraform deploys the VNet,
subnets, NSGs, Bastion, the Catalyst 8000V, and the ISE VM, and everything
is committed and pushed. The router works. ISE deploys and its operating
system boots and provisions cleanly, but its application layer (the admin
GUI and iseadmin access) has not finished starting. That is the one open
problem, and it is an ISE appliance issue, not a Terraform bug.

Both VMs are deallocated right now to stop compute billing.

## What works

- The full Terraform build: `terraform apply` stands up all 19 resources.
- The Catalyst 8000V. Its SSH is reachable through a Bastion tunnel and
  IOS-XE responds.
- ISE deployment and OS provisioning. The serial console shows
  `User provided data validation Passed` and `Provisioning complete`, so the
  day-0 bootstrap is accepted.
- All quality gates: fmt, validate, trivy, and pre-commit with gitleaks.

## What is blocked: ISE application startup

ISE's OS is up and its SSH transport answers, but the admin GUI on port 443
never starts and iseadmin key login is refused. Both of those come up only
after ISE finishes initializing its application, so both failing means the
app init has not completed.

What we ruled out:

- Not the day-0 format. The original bug was real and is fixed: ISE 3.4 reads
  its bootstrap from `user_data` (not `custom_data`), as multi-line
  key=value, and the NTP key is `primaryntpserver` (not `ntpserver`). This
  matches Cisco's official ISE 3.4 Terraform.
- Not disk speed. The app failed to come up on StandardSSD after four hours
  and on Premium SSD after an hour. The disk is now Premium either way.
- Not the network. The subnet NSG allows 22, 443, and 49 from the VNet, and
  Bastion tunnels work (proven against the router).

Leading suspect: a time-sync stall. Every boot, the Azure agent logs a DNS
failure ("Name or service not known") for an Azure endpoint. If ISE cannot
resolve or reach its NTP server, its app init can hang. The current config
points NTP at `time.windows.com`, which depends on DNS. The fix under test is
to use an NTP IP address instead, removing the DNS dependency.

ISE does not log its app init to the serial console, so confirming the cause
needs interactive access.

## Two ways to resume

### Option A: fast az CLI iteration (recommended first)

`scripts/90-ise-deploy.sh` deploys a test ISE into the existing VNet in one
command, so you can change one field and redeploy without a 20-minute
Terraform cycle. It defaults NTP to `168.63.129.16` (Azure's platform time
source, reachable by IP with no DNS), which directly tests the time-sync
theory. It uses the name `ise-test` and IP `10.80.0.70` so it does not touch
the Terraform-managed `ise-lab`.

    ISE_PASSWORD="$(terraform -chdir=terraform output -raw ise_admin_password)" \
      scripts/90-ise-deploy.sh

Wait 30 to 45 minutes, then check the GUI. If it comes up, the NTP-by-IP
change was the fix. Port the working values into `terraform/modules/ise`
(the `primaryntpserver` line and the userdata template) and rebuild the real
`ise-lab`.

### Option B: diagnose the current VM from the serial console

Start `ise-lab`, open the Azure portal serial console, and log in as
iseadmin (password from `terraform -chdir=terraform output -raw ise_admin_password`).
Then:

    show application status ise    # which service is stuck
    show ntp                       # is time synced
    ping time.windows.com          # does DNS resolve and reach NTP

If NTP is unsynced or the ping fails, that confirms the time-sync theory and
Option A's IP-based NTP is the fix.

## Azure resources right now

- Resource group `tacacs-tue-rg` in eastus2.
- `ise-lab` and `c8kv-lab`: deallocated. Start them with
  `az vm start -g tacacs-tue-rg -n <name>`.
- Bastion Standard, disks, and the Bastion public IP still exist and bill a
  small amount. To stop all cost, run `terraform -chdir=terraform destroy`.
  The code redeploys the whole lab cleanly.

## Pending, unrelated to ISE

A committed change to the c8000v admin password generation
(`min_upper`/`min_lower`/`min_numeric`) has not been applied. A full
`terraform apply` will want to replace the router VM because of it. Apply it
on purpose during a router maintenance window, or accept the short router
rebuild. The TACACS+ shared secret is unaffected.

## Key commands to pick back up

    # Start the VMs again
    az vm start -g tacacs-tue-rg -n ise-lab
    az vm start -g tacacs-tue-rg -n c8kv-lab

    # Tunnels (each holds a terminal)
    terraform -chdir=terraform output bastion_tunnel_commands

    # Retrieve secrets when needed
    terraform -chdir=terraform output -raw ise_admin_password
    terraform -chdir=terraform output -raw tacacs_shared_secret

## Notes

Detailed session notes, including the full ISE debugging trail, are in
`.superpowers/sdd/morning-notes.md` (gitignored scratch, local only).
