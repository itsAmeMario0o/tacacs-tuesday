#!/usr/bin/env bash
# Manage the two Bastion tunnels the lab depends on:
#   router SSH  -> localhost:2222
#   ISE HTTPS   -> localhost:8443  (GUI and ERS API)
#
# Usage: scripts/30-tunnels.sh start|stop|status
#
# start is idempotent: a tunnel that is already up is left alone, so
# running it again after one dies only restarts the dead one. Tunnels
# run detached with logs and pidfiles under ~/.tacacs-tunnels, so they
# do not occupy terminals and survive the shell that started them.
set -euo pipefail

RG="tacacs-tue-rg"
BASTION="bas-lab"
STATE_DIR="${HOME}/.tacacs-tunnels"

port_listening() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN > /dev/null 2>&1
}

start_tunnel() {
  local name="$1" vm_name="$2" resource_port="$3" local_port="$4"
  if port_listening "${local_port}"; then
    echo "${name}: already listening on ${local_port}"
    return 0
  fi
  local vm_id
  vm_id="$(az vm show -g "${RG}" -n "${vm_name}" --query id -o tsv)"
  nohup az network bastion tunnel -n "${BASTION}" -g "${RG}" \
    --target-resource-id "${vm_id}" \
    --resource-port "${resource_port}" --port "${local_port}" \
    >> "${STATE_DIR}/${name}.log" 2>&1 &
  echo "$!" > "${STATE_DIR}/${name}.pid"
  local tries
  for tries in $(seq 1 30); do
    if port_listening "${local_port}"; then
      echo "${name}: up on localhost:${local_port}"
      return 0
    fi
    sleep 1
  done
  echo "${name}: did not come up in 30s, see ${STATE_DIR}/${name}.log" >&2
  return 1
}

stop_tunnel() {
  local name="$1" local_port="$2"
  local pid_file="${STATE_DIR}/${name}.pid"
  if [[ -f "${pid_file}" ]]; then
    kill "$(cat "${pid_file}")" 2> /dev/null || true
    rm -f "${pid_file}"
  fi
  # Catch tunnels started outside this script that hold the port.
  local holder
  holder="$(lsof -nP -tiTCP:"${local_port}" -sTCP:LISTEN 2> /dev/null || true)"
  if [[ -n "${holder}" ]]; then
    kill "${holder}" 2> /dev/null || true
  fi
  echo "${name}: stopped"
}

show_status() {
  if port_listening 2222; then
    echo "router: up on localhost:2222"
  else
    echo "router: DOWN"
  fi
  if port_listening 8443; then
    local http_code
    http_code="$(curl -sk -m 5 -o /dev/null -w '%{http_code}' https://127.0.0.1:8443/ || true)"
    echo "ise:    up on localhost:8443 (GUI answers HTTP ${http_code})"
  else
    echo "ise:    DOWN"
  fi
}

mkdir -p "${STATE_DIR}"
case "${1:-}" in
  start)
    start_tunnel "router" "c8kv-lab" 22 2222
    start_tunnel "ise" "ise-test" 443 8443
    show_status
    ;;
  stop)
    stop_tunnel "router" 2222
    stop_tunnel "ise" 8443
    ;;
  status)
    show_status
    ;;
  *)
    echo "Usage: $0 start|stop|status" >&2
    exit 1
    ;;
esac
