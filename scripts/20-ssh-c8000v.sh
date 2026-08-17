#!/usr/bin/env bash
# SSH to the C8000V through the Bastion tunnel with the repo key (ADR 0007).
# The tunnel must already be up (see bastion_tunnel_commands terraform
# output). Pass an IOS command to run it and exit, or nothing for a shell.
#
#   scripts/20-ssh-c8000v.sh "show ip interface brief"
#
# PubkeyAcceptedAlgorithms includes ssh-rsa because IOS-XE offers RSA
# signatures OpenSSH clients no longer accept by default. Host key checking
# is off because the router mints a new host key every rebuild (ADR 0004).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TUNNEL_PORT="${TUNNEL_PORT:-2222}"
KEY_FILE="${REPO_ROOT}/keys/c8000v_admin"

if [[ ! -f "${KEY_FILE}" ]]; then
  echo "Missing ${KEY_FILE}. Run terraform apply first (ADR 0007)." >&2
  exit 1
fi

exec ssh \
  -i "${KEY_FILE}" \
  -o PubkeyAcceptedAlgorithms=+ssh-rsa,rsa-sha2-256,rsa-sha2-512 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -p "${TUNNEL_PORT}" \
  labadmin@127.0.0.1 "$@"
