# Device access

How to reach both devices from the desktop. Everything goes through
Bastion; nothing in this lab has a public IP.

## Two tunnels at once

Bastion (Standard SKU) supports concurrent sessions, so the ISE GUI and
the router CLI can be open at the same time. This was verified on
2026-08-18 with both tunnels live and both devices answering
simultaneously. The only rule: each tunnel needs its own free local
port. If `az network bastion tunnel` says "Defined port is currently
unavailable", the local port is already taken, usually by a tunnel you
already have running. Pick another port or close the old tunnel.

The easy way is the tunnel manager, which detaches both tunnels from
the terminal (logs and pidfiles in `~/.tacacs-tunnels`):

    scripts/30-tunnels.sh start     # idempotent; restarts only what is down
    scripts/30-tunnels.sh status    # both ports, plus an ISE GUI probe
    scripts/30-tunnels.sh stop

Run `start` again anytime a tunnel dies (Bastion idles them out
eventually); it leaves the healthy one alone. Before a demo: `status`,
and if anything says DOWN, `start`.

The manual equivalents, if you want a tunnel pinned to a terminal:

    # Terminal 1: ISE GUI on local 8443
    az network bastion tunnel -n bas-lab -g tacacs-tue-rg \
      --target-resource-id "$(az vm show -g tacacs-tue-rg -n ise-test --query id -o tsv)" \
      --resource-port 443 --port 8443

    # Terminal 2: router SSH on local 2222
    az network bastion tunnel -n bas-lab -g tacacs-tue-rg \
      --target-resource-id "$(az vm show -g tacacs-tue-rg -n c8kv-lab --query id -o tsv)" \
      --resource-port 22 --port 2222

## ISE GUI

With the 8443 tunnel up, browse to `https://127.0.0.1:8443`. Accept the
self-signed certificate warning. Sign in as `iseadmin` with the password
from:

    terraform -chdir=terraform output -raw ise_admin_password

Type it into the login form and nowhere else. The first login offers a
tour; skip it.

## Router CLI

With the 2222 tunnel up:

    scripts/20-ssh-c8000v.sh                        # interactive shell
    scripts/20-ssh-c8000v.sh "show ip int brief"    # one command and out

The script logs in as `labadmin` with the key from `keys/` (ADR 0007),
so there is no password prompt. Password login still works as the AAA
fallback; the password is in the `c8000v_admin_password` Terraform
output.

## ISE CLI and serial console

Rarely needed. SSH: tunnel to `ise-test` port 22 and log in as
`iseadmin` with the `ise-test-key` PEM downloaded during the Portal
deploy (that deploy predates ADR 0007, so it is not the repo key). The
Azure Serial Console in the Portal also works with the GUI password and
is the right tool when ISE is mid-boot and SSH is refused.

## Demo callout: the post-quantum warning

When the SSH script connects to the router, OpenSSH prints a warning
that the session is not using a post-quantum key exchange and may be
vulnerable to "store now, decrypt later" attacks. That is the local
OpenSSH client (10.x) judging the key-exchange algorithms IOS-XE offers,
not output from the router itself. Frame it accurately in the demo, and
it lands well with a security audience: harvest-now-decrypt-later is
exactly the pattern attributed to Salt Typhoon's telecom intrusions, and
here is a stock client flagging classical key exchange on network
infrastructure gear in real time. The takeaway for the audience is that
crypto agility on infrastructure devices is now table stakes.
