# ADR 0002: Permissive but present NSGs

## Status

Accepted, 2026-07-30.

## Context

This is a short-lived demo lab. An NSG rule that quietly blocks TACACS+
or a Bastion tunnel costs troubleshooting hours the schedule does not
have. The VMs have no public IPs, so there is no internet exposure for a
strict NSG to guard against anyway.

The flows the lab needs, verified:

| Flow | Port | Verified against |
|---|---|---|
| C8000V to ISE, TACACS+ | TCP/49 | The demo core |
| Desktop to ISE GUI and ERS API, via Bastion | TCP/443 | ISE 3.1+ serves ERS, OpenAPI, and MnT through its API gateway on 443. The ise-mcp-server README confirms it targets 443, not the legacy 9060. |
| Desktop to C8000V SSH, via Bastion | TCP/22 | The ios-xe-mcp-server README: Netmiko over SSH 22 |
| VMs out to DNS, NTP, HTTPS | 53, 123, 443 | Standard egress |

Azure's default NSG rules already allow all traffic inside the VNet and
deny everything inbound from the internet. That is the posture we want.

## Decision

- Attach one NSG to `snet-mgmt` and one to `snet-nad`, so every VM sits
  behind one.
- Keep the Azure default rules. Add allow rules for TCP/49, 443, and 22
  from the VNet so the intent is written down. These duplicate what the
  defaults already permit, so removing or reordering them can never
  break traffic.
- Add no custom deny rules. Nothing in our config can block east-west
  traffic.
- Leave `AzureBastionSubnet` without an NSG. Attaching one requires
  Microsoft's mandatory rule set, and getting it wrong is the most
  common way people break Bastion.

## Options considered

A least-privilege rule set. Rejected: the exposure it would reduce is
already zero, and its failure mode is the silent east-west block this
lab cannot afford to debug.

No NSGs at all. Rejected: basic hygiene, and "each instance has an NSG"
is a sentence we want to say truthfully in front of a security audience.
