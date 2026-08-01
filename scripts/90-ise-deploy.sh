#!/usr/bin/env bash
# Deploy Cisco ISE 3.4 into the existing lab VNet with the az CLI.
#
# This is a fast-iteration helper for getting ISE's day-0 bootstrap right.
# A full Terraform rebuild takes 20+ minutes per attempt; this lets you
# change one field (NTP, DNS, timezone) and redeploy quickly. Once a config
# boots cleanly, port the same values into terraform/modules/ise.
#
# It reuses the Terraform-built network (VNet, subnet, subnet NSG), so run
# terraform apply for the foundation first. It does not touch Terraform state,
# so it uses its own VM name and IP by default (ise-test / 10.80.0.70) to
# avoid colliding with the module's ise-lab.
#
# Prereqs:
#   - az logged in (az account show)
#   - terraform/images.auto.tfvars present (scripts/10-resolve-images.sh)
#   - marketplace terms accepted (scripts/10-resolve-images.sh ACCEPT_TERMS=yes)
#   - ISE_PASSWORD set in the environment, e.g.:
#       ISE_PASSWORD="$(terraform -chdir=terraform output -raw ise_admin_password)"
#
# Usage:
#   ISE_PASSWORD=... scripts/90-ise-deploy.sh
#   ISE_PASSWORD=... NTP_SERVER=10.0.0.5 VM_NAME=ise-lab PRIVATE_IP=10.80.0.68 scripts/90-ise-deploy.sh
set -euo pipefail

RG="${RG:-tacacs-tue-rg}"
LOCATION="${LOCATION:-eastus2}"
VNET="${VNET:-tacacs-tue-vnet}"
SUBNET="${SUBNET:-snet-mgmt}"

VM_NAME="${VM_NAME:-ise-test}"
VM_SIZE="${VM_SIZE:-Standard_D4s_v4}"
PRIVATE_IP="${PRIVATE_IP:-10.80.0.70}"
OS_DISK_GB="${OS_DISK_GB:-300}"
ADMIN_USER="iseadmin"

# ISE day-0 fields. NTP defaults to Azure's platform time source by IP, not a
# hostname. A boot-time DNS failure is the suspected cause of ISE app init
# stalling, and an IP removes the DNS dependency. Override NTP_SERVER to test.
HOSTNAME_ISE="${HOSTNAME_ISE:-${VM_NAME}}"
DNS_SERVER="${DNS_SERVER:-168.63.129.16}"
DNS_DOMAIN="${DNS_DOMAIN:-lab.internal}"
NTP_SERVER="${NTP_SERVER:-168.63.129.16}"
TIMEZONE="${TIMEZONE:-UTC}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGES_TFVARS="${REPO_ROOT}/terraform/images.auto.tfvars"

# Read one field from the ise_image block of images.auto.tfvars so the image
# coordinates are never hardcoded (they are pinned by 10-resolve-images.sh).
read_image_field() {
  local field="$1"
  awk -v want="${field}" '
    /ise_image[[:space:]]*=[[:space:]]*\{/ { inblk = 1; next }
    inblk && $1 == want { gsub(/[",]/, "", $3); print $3; exit }
    inblk && /\}/ { inblk = 0 }
  ' "${IMAGES_TFVARS}"
}

require_prereqs() {
  if [[ ! -f "${IMAGES_TFVARS}" ]]; then
    echo "Missing ${IMAGES_TFVARS}. Run scripts/10-resolve-images.sh first." >&2
    exit 1
  fi
  if [[ -z "${ISE_PASSWORD:-}" ]]; then
    echo "Set ISE_PASSWORD, e.g.:" >&2
    echo "  ISE_PASSWORD=\"\$(terraform -chdir=terraform output -raw ise_admin_password)\"" >&2
    exit 1
  fi
}

# ISE 3.4 reads its bootstrap from user_data as multi-line key=value pairs.
# Field names are ISE-specific: primarynameserver, primaryntpserver.
build_user_data() {
  cat <<EOF
hostname=${HOSTNAME_ISE}
dnsdomain=${DNS_DOMAIN}
primarynameserver=${DNS_SERVER}
primaryntpserver=${NTP_SERVER}
timezone=${TIMEZONE}
password=${ISE_PASSWORD}
ersapi=yes
openapi=yes
pxGrid=no
pxgrid_cloud=no
EOF
}

main() {
  require_prereqs

  local publisher offer sku version
  publisher="$(read_image_field publisher)"
  offer="$(read_image_field offer)"
  sku="$(read_image_field sku)"
  version="$(read_image_field version)"

  echo "Deploying ${VM_NAME} into ${VNET}/${SUBNET} at ${PRIVATE_IP}"
  echo "Image:  ${publisher}:${offer}:${sku}:${version}"
  echo "NTP:    ${NTP_SERVER}   DNS: ${DNS_SERVER}"

  az vm create \
    --resource-group "${RG}" \
    --name "${VM_NAME}" \
    --location "${LOCATION}" \
    --image "${publisher}:${offer}:${sku}:${version}" \
    --plan-name "${sku}" \
    --plan-product "${offer}" \
    --plan-publisher "${publisher}" \
    --size "${VM_SIZE}" \
    --vnet-name "${VNET}" \
    --subnet "${SUBNET}" \
    --private-ip-address "${PRIVATE_IP}" \
    --public-ip-address "" \
    --nsg "" \
    --storage-sku Premium_LRS \
    --os-disk-size-gb "${OS_DISK_GB}" \
    --admin-username "${ADMIN_USER}" \
    --generate-ssh-keys \
    --user-data "$(build_user_data)" \
    --only-show-errors

  # Managed boot diagnostics so the serial console works if it stalls.
  az vm boot-diagnostics enable \
    --resource-group "${RG}" --name "${VM_NAME}" --only-show-errors >/dev/null

  echo "Deployed. ISE app build takes 30-45 min; watch the serial console."
  echo "Reach the GUI once up:"
  echo "  az network bastion tunnel -n bas-lab -g ${RG} \\"
  echo "    --target-resource-id \$(az vm show -g ${RG} -n ${VM_NAME} --query id -o tsv) \\"
  echo "    --resource-port 443 --port 8443"
}

main "$@"
