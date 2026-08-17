# Deploying ISE from the Azure Portal

Terraform builds everything except ISE: the resource group, VNet, subnets,
NSGs, Bastion, and the C8000V. ISE is deployed by hand afterward, either
with `scripts/90-ise-deploy.sh` (az CLI, same values baked in) or through
the Portal as described here. ADR 0006 covers why ISE is not in Terraform;
the short version is that Azure's 20-minute OS-provisioning timeout fires
before Cisco's marketplace image reports ready, so `terraform apply` fails
on a VM that is actually fine.

Run `terraform apply` first. This guide assumes `tacacs-tue-rg` and its
network already exist.

## Find the right listing

Search the Portal for "Cisco Identity Services Engine". Cisco publishes a
dedicated solution template per version (for example "Cisco Identity
Services Engine (ISE) BYOL 3.5"). Use it. The template asks for the day-0
fields directly, so there is no user_data block to paste. Field names and
order are handled for you, which removes the most error-prone part of a
manual deploy.

Version note: our Terraform image pin is 3.4, but Cisco's suggested release
as of mid-2026 is 3.5 Patch 3. Either works with this guide. If you deploy
with the az CLI script instead and want 3.5, re-pin first:
`ISE_SKU=cisco-ise_3_5 scripts/10-resolve-images.sh`.

## Basics tab

| Field | Value |
|---|---|
| Resource group | `tacacs-tue-rg` (existing) |
| VM name | `ise-test` |
| Region | East US 2 |
| Size | `Standard_D8s_v4` |
| OS disk | Premium SSD, 300 GiB |

The size and disk are Cisco minimums, not suggestions. A smaller VM boots
the OS but starves the ISE application, and the GUI never comes up. We
learned this the slow way: four failed deploys on `D4s_v4`.

## Network Settings tab

| Field | Value |
|---|---|
| Virtual Network | `tacacs-tue-vnet` |
| Subnet | `snet-mgmt` |
| Network Security Group | `tacacs-tue-nsg-mgmt` |
| SSH public key source | Generate new key pair |
| SSH Key Type | RSA |
| Key pair name | `ise-test-key` |
| Private IP Address | `10.80.0.70` |
| Public IP Address | **None** |
| DNS domain name | `tacacs.lab` |
| Primary Name Server | `168.63.129.16` |
| Secondary/Tertiary Name Server | blank |
| Primary NTP Server | `time.windows.com` |
| Secondary/Tertiary NTP Server | blank |

Details that matter:

- **Public IP must be None.** The template defaults to creating one. ISE is
  reached through Bastion only; a public IP puts the admin plane on the
  internet.
- **NSG:** pick the existing `tacacs-tue-nsg-mgmt`. It is the same NSG
  already attached to the subnet (TACACS+ 49, HTTPS 443, SSH 22, from
  inside the VNet), so the rules stay in one place. Do not let the Portal
  create a new one.
- **SSH key type is RSA** because Azure rejects Ed25519 for the admin user
  on this image. The key hardly matters day to day: ISE only installs it
  after the application finishes starting, and the serial console and GUI
  use the password instead.
- **NTP must be a real NTP server.** Never use `168.63.129.16` here. That
  address is Azure's DNS and wireserver VIP, and it does not speak NTP. ISE
  will not finish starting without a synced clock. `time.windows.com` by
  name is safe because DNS points at Azure's resolver, which resolves
  public names.
- **The domain is `tacacs.lab` because the template said so.** The form's
  validation rejects `lab.internal` (its regex appears to want a short
  TLD), and the domain does not need to be resolvable anyway. The az CLI
  script uses the same value so both paths match. The router was updated
  to `ip domain name tacacs.lab` live over SSH; its Terraform day-0
  template still says `lab.internal` because changing custom_data forces
  a VM replacement. Flip the c8000v `domain_name` default at the next
  full rebuild.
- The private IP `10.80.0.70` is what the scripts and runbooks assume.

## Services tab

| Field | Value |
|---|---|
| ERS | yes |
| OpenAPI | yes |
| pxGrid | yes |
| pxGrid Cloud | no |

ERS and OpenAPI are what the MCP suite and Ansible use to talk to ISE.
The lab does not use pxGrid, but the August 2026 deploy went out with it
enabled and that is harmless, so the table records what actually runs.
All of these can be flipped later in the GUI under Administration >
System > Settings > API Settings, so a wrong toggle here is not a
redeploy.

## User Details tab

Username `iseadmin`. The password comes from Terraform so it lives in one
place:

    terraform -chdir=terraform output -raw ise_admin_password

Type it into the Portal form and nowhere else. This password is the one
that matters: it is the GUI login, the ISE CLI login, and the serial
console login.

If the template asks for timezone, use `Etc/UTC` (that exact string, not
`UTC`; it matches the user_data Cisco's own deploys generate).

## After you click Create

Azure offers the `ise-test-key` private key as a download when the
deployment starts. Save it and `chmod 600` it.

The VM lands in a few minutes. ISE's first boot then takes 45 to 60
minutes. The GUI on 443 stays down and SSH refuses the key for that whole
window. Neither is a failure sign.

Do not wait blind. About 10 minutes in, open the VM's Serial Console in the
Portal, log in as `iseadmin` with the password, and run:

    show application status ise    # which services are up or stuck
    show ntp                       # the clock must be synchronized
    show clock                     # what time ISE thinks it is

If NTP is not synchronized, stop and fix that before anything else; the
application will not finish starting without it. If services are marching
toward `running`, let it cook.

Once the app is up, tunnel to the GUI:

    az network bastion tunnel -n bas-lab -g tacacs-tue-rg \
      --target-resource-id "$(az vm show -g tacacs-tue-rg -n ise-test --query id -o tsv)" \
      --resource-port 443 --port 8443

Then browse to `https://127.0.0.1:8443` and log in as `iseadmin`.

## Teardown notes

Deleting the VM leaves its NIC and OS disk behind, and the VNet will not
tear down while the NIC exists. Delete all three. Also, `terraform destroy`
gets a 409 on a deallocated VM; start the VM first, then destroy.
