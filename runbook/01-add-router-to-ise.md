# Add the router to ISE as a TACACS+ network device

One-time setup that makes demo 1 possible: ISE authenticates and
authorizes logins to the C8000V over TACACS+. Every step ends with a
check; do not move on until the check passes.

Prerequisites: both devices reachable per `00-device-access.md`. The
router's AAA config already points at ISE (10.80.0.70) with the shared
secret from day-0; nothing on the router needs to change here.

## 1. Enable the Device Admin service

GUI: Administration > System > Deployment > click the node > check
**Enable Device Admin Service** > Save. Services restart for a few
minutes.

ISE shows a warning here: TACACS+ cannot use modern encryption because
of protocol restrictions, and Cisco recommends IPsec between ISE and the
device. Expected, and worth keeping as a talking point (see the note at
the end). Acknowledge and continue.

Check: the node's service list includes Device Admin, and port 49
accepts connections.

## 2. Add the router as a network device

Administration > Network Resources > Network Devices > Add.

| Field | Value |
|---|---|
| Name | `c8kv-lab` |
| IP address | `10.80.0.132 / 32` |
| Device profile | Cisco |
| TACACS Authentication Settings | enable, then paste the shared secret |

The secret comes from:

    terraform -chdir=terraform output -raw tacacs_shared_secret

The IP must match the router exactly. TACACS+ from an unknown source IP
is silently dropped, which looks like empty Live Logs and no error
anywhere.

Check: the device appears in the list.

## 3. Create the demo identity

Administration > Identity Management > Identities > Users > Add. A
single internal user, for example `netadmin`, with a password of your
choosing. No groups needed yet.

Check: the user is listed and enabled.

## 4. Build the authorization results

Work Centers > Device Administration > Policy Elements > Results.

- TACACS Profile: shell profile with default privilege 15.
- TACACS Command Set: check "Permit any command that is not listed
  below" and leave the list empty.

Check: both appear under Results.

## 5. Wire the policy set

Work Centers > Device Administration > Device Admin Policy Sets. Use the
default set: authentication against Internal Users, and an authorization
rule that maps the user (or all users, fine for the demo) to the shell
profile and command set from step 4. Save.

Check: the rule sits above the default deny in the list.

## 6. Test from an existing router session

From a session you are already in (so a broken policy cannot lock you
out):

    scripts/20-ssh-c8000v.sh
    test aaa group ISE-GROUP netadmin <password> legacy

Check: "User was successfully authenticated." If the router reports the
server is unreachable instead, the NAD IP in step 2 is wrong or the
Device Admin service is not up.

## 7. End-to-end login

Open a new SSH session to the router as `netadmin` with its password.
This authenticates through TACACS+, not the local user.

    ssh -p 2222 netadmin@127.0.0.1

Check: you land at privilege 15, and Work Centers > Device
Administration > Overview > TACACS Live Log shows the Pass. That Live
Log entry is the proof point demo 1 is built around.

Idempotency check: log in a second time; same result, new log entry.

## Troubleshooting

**Live Log shows `13078 Invalid TACACS+ authorization request packet -
possibly malformed packet`.** That is a shared-secret mismatch, not
corruption: ISE cannot decrypt the body, so it reads as malformed. The
usual cause is a bad paste into the NAD form. Re-copy with
`terraform -chdir=terraform output -raw tacacs_shared_secret | pbcopy`
(exact bytes, nothing displayed) and re-paste. This happened on the
first bring-up, 2026-08-18.

**Permit `labadmin` in the policy before the secret works, not after.**
Once ISE can decrypt, it authorizes every session, including local-user
ones, and the `local` fallback only engages when ISE is unreachable, not
when it rejects. Without a rule for `labadmin`, its sessions start
failing the moment the secret is right. The `Permit-NetAdmin` rule
matches `netadmin OR labadmin` for this reason, and `labadmin` also
exists as an ISE internal user so password logins keep working while ISE
is up.

## Safety net

If ISE is down or unreachable, the router falls back to the local
`labadmin` account (password in Terraform output, key in `keys/`). The
fallback triggers on unreachable only. A wrong password is still a
clean reject; that is TACACS+ working, not failing.

## Talking point: the IPsec warning

The warning in step 1 is honest and worth repeating to a security
audience rather than hiding: TACACS+ dates to a time before modern
transport crypto, and its body obfuscation is not encryption by today's
standard. Cisco's answer is IPsec between ISE and the device, which this
lab skips deliberately (one router, one demo, private VNet). In a
production conversation this becomes an argument for the governed-change
path in demo 3: the fewer humans typing at privileged CLIs over legacy
protocols, the smaller that exposure gets.
