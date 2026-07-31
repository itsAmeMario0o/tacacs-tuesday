#!/usr/bin/env bash
# Resolve the current Cisco ISE and Catalyst 8000V marketplace images and
# pin exact versions into images.auto.tfvars. Terms acceptance changes
# subscription state, so it only happens when ACCEPT_TERMS=yes, after a
# human has reviewed the resolved images. Re-running is safe.
set -euo pipefail

LOCATION="${LOCATION:-eastus2}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_FILE="${REPO_ROOT}/terraform/images.auto.tfvars"

# Find the publisher named exactly "cisco" rather than trusting a blog post.
find_publisher() {
  az vm image list-publishers --location "${LOCATION}" \
    --query "[?name=='cisco'].name" -o tsv
}

# Newest offer matching a pattern, e.g. "ise" or "c8000v".
find_offer() {
  local publisher="$1" pattern="$2"
  az vm image list-offers --location "${LOCATION}" --publisher "${publisher}" \
    --query "[?contains(name, '${pattern}')].name" -o tsv | sort | tail -n 1
}

# Newest SKU for an offer. BYOL SKUs are preferred when present.
find_sku() {
  local publisher="$1" offer="$2"
  local skus
  skus="$(az vm image list-skus --location "${LOCATION}" \
    --publisher "${publisher}" --offer "${offer}" --query "[].name" -o tsv)"
  if echo "${skus}" | grep -q 'byol'; then
    echo "${skus}" | grep 'byol' | sort | tail -n 1
  else
    echo "${skus}" | sort | tail -n 1
  fi
}

# Newest version for a SKU, pinned exactly.
find_version() {
  local publisher="$1" offer="$2" sku="$3"
  az vm image list --location "${LOCATION}" --publisher "${publisher}" \
    --offer "${offer}" --sku "${sku}" --all \
    --query "sort_by([], &version)[-1].version" -o tsv
}

accept_terms() {
  local publisher="$1" offer="$2" sku="$3"
  az vm image terms accept --publisher "${publisher}" --offer "${offer}" \
    --plan "${sku}" --only-show-errors > /dev/null
}

main() {
  local publisher
  publisher="$(find_publisher)"
  if [[ -z "${publisher}" ]]; then
    echo "No 'cisco' publisher found in ${LOCATION}" >&2
    exit 1
  fi

  local ise_offer c8k_offer
  ise_offer="$(find_offer "${publisher}" "ise")"
  c8k_offer="$(find_offer "${publisher}" "c8000v")"

  local ise_sku c8k_sku
  ise_sku="$(find_sku "${publisher}" "${ise_offer}")"
  c8k_sku="$(find_sku "${publisher}" "${c8k_offer}")"

  local ise_version c8k_version
  ise_version="$(find_version "${publisher}" "${ise_offer}" "${ise_sku}")"
  c8k_version="$(find_version "${publisher}" "${c8k_offer}" "${c8k_sku}")"

  echo "ISE:    ${publisher} / ${ise_offer} / ${ise_sku} / ${ise_version}"
  echo "C8000V: ${publisher} / ${c8k_offer} / ${c8k_sku} / ${c8k_version}"

  if [[ "${ACCEPT_TERMS:-no}" == "yes" ]]; then
    accept_terms "${publisher}" "${ise_offer}" "${ise_sku}"
    accept_terms "${publisher}" "${c8k_offer}" "${c8k_sku}"
    echo "Marketplace terms accepted for both images."
  else
    echo "Terms NOT accepted. Review the images above, then re-run with ACCEPT_TERMS=yes."
  fi

  cat > "${OUT_FILE}" <<EOF
# Written by scripts/10-resolve-images.sh. Do not edit by hand.
ise_image = {
  publisher = "${publisher}"
  offer     = "${ise_offer}"
  sku       = "${ise_sku}"
  version   = "${ise_version}"
}
c8000v_image = {
  publisher = "${publisher}"
  offer     = "${c8k_offer}"
  sku       = "${c8k_sku}"
  version   = "${c8k_version}"
}
EOF

  echo "Wrote ${OUT_FILE}"
}

main "$@"
