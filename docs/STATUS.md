# Project status and handoff

Last updated 2026-08-02.

## Where things stand

Everything in Azure is torn down. `terraform destroy` removed the whole
project, including the resource group, and the manually-deployed ISE VM was
deleted first since it lived outside Terraform. Azure cost is zero. The code
in this repo and this document are the state to pick up from.

The infrastructure code works. The open problem is ISE: it deploys and its OS
boots, but the application never finishes starting, so the admin GUI never
comes up. We found and fixed one real cause this session, but ISE still did
not come up at the correct size, so at least one more cause remains.

## The plan going forward

ISE is no longer built by Terraform (ADR 0006). Terraform builds the network,
Bastion, and the router. ISE is deployed on its own with the az CLI into the
VNet Terraform creates.

Next session:

1. `terraform apply` builds the foundation, Bastion, and C8000V. It does not
   build ISE. The ISE module and its outputs are commented out, and
   `random_password.ise_admin` stays so the ISE password still comes from one
   place.
2. Deploy ISE into the VNet with `scripts/90-ise-deploy.sh`.
3. Diagnose why the ISE application does not finish starting, using the Azure
   Serial Console (see below). Do this first, before another blind rebuild.

## The open problem: ISE application never starts

ISE deploys and the OS provisions cleanly every time. The serial console
shows `User provided data validation Passed` and the VM runs. But the admin
GUI on port 443 never binds, and the `iseadmin` SSH key is refused because
ISE only installs that key once the application is up. Four deploys, same
result.

### Found and fixed: undersized VM

We were deploying `Standard_D4s_v4` (4 vCPU, 16 GB). Cisco's smallest
supported ISE instance on Azure is `Standard_D8s_v4` (8 vCPU, 32 GB), double
on both counts. An undersized VM boots the OS but starves the ISE
application, which matches the symptom exactly. The size default is now
`Standard_D8s_v4` in both `terraform/variables.tf` and
`scripts/90-ise-deploy.sh`.

Sources: Cisco ISE 3.4 Installation Guide (appliance and VM requirements) and
the Cisco ISE on Azure native cloud guide.

### Still open: the size fix was necessary but not sufficient

ISE did not come up even at `D8s_v4`, so something else is also wrong. The
leading suspects, in order:

- Time sync. ISE will not fully start without a synced clock; its internal CA
  depends on it. The failing deploys pointed NTP at `168.63.129.16`, which is
  Azure's DNS and wireserver address, not an NTP server, so ISE's clock almost
  certainly never synced. This was a mistake on my part. The script now
  defaults NTP to a real server (`162.159.200.123`, time.cloudflare.com, by
  IP so there is no DNS dependency). This is the first thing to test.
- DNS self-resolution. ISE wants to resolve its own hostname. We used the
  domain `lab.internal` with Azure DNS, which cannot resolve it. ISE usually
  warns and continues, but it is worth ruling out.

Ruled out: the day-0 format (`user_data`, multi-line, with the
`primaryntpserver` key, is correct and accepted), disk speed (Premium SSD),
and the network path (the NSG allows 22, 443, and 49, and Bastion tunnels
work against the router).

### How to actually diagnose it next time

There is no way to see which service is stuck from outside. SSH is refused
until the app is up, and ISE does not log its app init to the boot
diagnostics serial log. The one channel that works is the Azure Serial
Console. After ISE is redeployed, open the portal, go to the ISE VM, open the
serial console, log in as `iseadmin` with the password from Terraform, and
run:

    show application status ise    # which service is stuck
    show ntp                       # is the clock synced
    show clock                     # what time does ISE think it is

If NTP is unsynced, that confirms the time-sync theory and the new NTP
default is the fix. Do this before spending another 30 to 45 minute rebuild
on a guess.

## How to pick back up

    # Build the network, Bastion, and router (no ISE)
    terraform -chdir=terraform init
    terraform -chdir=terraform apply

    # Deploy ISE into the VNet. The script defaults to D8s_v4 and a real NTP
    # server by IP. It reads the admin password from Terraform.
    ISE_PASSWORD="$(terraform -chdir=terraform output -raw ise_admin_password)" \
      scripts/90-ise-deploy.sh

    # Watch the Azure Serial Console during the 30 to 45 minute app build.
    # The script prints the Bastion tunnel command for the GUI once ISE is up.

The pinned marketplace image coordinates live in
`terraform/images.auto.tfvars`, which is gitignored and stays on disk between
sessions. If it is missing, regenerate it with `scripts/10-resolve-images.sh`.

## Notes

- Deleting the manual ISE VM leaves its NIC and OS disk behind. Delete all
  three, or the VNet will not tear down while the NIC is still attached.
- A deallocated VM cannot be powered off, so `terraform destroy` fails on it
  with a 409. Start the VM first, then destroy.
- The detailed debugging trail is in `.superpowers/sdd/morning-notes.md`,
  which is gitignored and local only.
