# ADR 0001: Two VMs, one VNet, Bastion Standard, eastus2

## Status

Accepted, 2026-07-30.

## Context

The lab needs Cisco ISE and a Catalyst 8000V that a local desktop can
reach. The desktop runs the MCP servers, Ansible, and a browser. Nothing
else in Azure has a job to do. An earlier sketch added a jumpbox as a
third VM, but Bastion tunnels already cover access, so we dropped it.

## Decision

- Resource group in eastus2, picked for better capacity than eastus at
  the same price. Every resource gets `owner` and `expires` tags.
- One VNet, `10.80.0.0/24`, with three subnets:

  | Subnet | Range | Holds |
  |---|---|---|
  | `AzureBastionSubnet` | 10.80.0.0/26 | Bastion Standard + public IP |
  | `snet-mgmt` | 10.80.0.64/26 | ISE VM, single NIC |
  | `snet-nad` | 10.80.0.128/26 | C8000V VM, single NIC |

- Neither VM gets a public IP. All access goes through
  `az network bastion tunnel` (local 8443 to ISE 443, local 2222 to
  C8000V 22).
- Bastion runs the Standard SKU with native client support turned on.
  Microsoft's docs are clear that `az network bastion tunnel` needs
  Standard or higher. Basic and Developer only do browser sessions in
  the portal.
- ISE gets a D4s-class size per Cisco's Azure guidance. The C8000V runs
  on a small D2-class size.

## Options considered

A jumpbox as a third VM. Rejected: Bastion tunnels give the desktop
everything a jumpbox would, and a jumpbox is one more VM to patch and
pay for.

A second NIC on the C8000V. Rejected: a TACACS+ device admin demo never
sends traffic through the router, so one management NIC is enough.

Public IPs with source IP allowlists. Rejected: more exposure for no
gain, since we need Bastion for the ISE GUI either way.
