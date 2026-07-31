#!/usr/bin/env bash
# Resolve the current Cisco ISE and Catalyst 8000V marketplace images and
# pin exact versions into images.auto.tfvars. Terms acceptance changes
# subscription state, so it only happens when ACCEPT_TERMS=yes, after a
# human has reviewed the resolved images. Re-running is safe.
set -euo pipefail

LOCATION="${LOCATION:-eastus2}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_FILE="${REPO_ROOT}/terraform/images.auto.tfvars"

# The demo pins a mature ISE release rather than floating to the newest.
# Set ISE_SKU="" on the command line to float to the newest versioned SKU.
ISE_SKU="${ISE_SKU:-cisco-ise_3_4}"

# Find the publisher named exactly "cisco" rather than trusting a blog post.
find_publisher() {
  az vm image list-publishers --location "${LOCATION}" \
    --query "[?name=='cisco'].name" -o tsv
}

# Newest offer matching a pattern. BYOL offers are preferred when present,
# so a PAYG offer that happens to sort last cannot win by accident.
find_offer() {
  local publisher="$1" pattern="$2"
  local offers
  offers="$(az vm image list-offers --location "${LOCATION}" --publisher "${publisher}" \
    --query "[?contains(name, '${pattern}')].name" -o tsv)"
  if echo "${offers}" | grep -q 'byol'; then
    echo "${offers}" | grep 'byol' | sort | tail -n 1
  else
    echo "${offers}" | sort | tail -n 1
  fi
}

# Newest SKU for an offer. An optional grep -E filter keeps licensing
# artifacts (e.g. cise-licenses) from outsorting real image SKUs; BYOL
# SKUs are preferred when no filter is given.
find_sku() {
  local publisher="$1" offer="$2" sku_filter="${3:-}"
  local skus
  skus="$(az vm image list-skus --location "${LOCATION}" \
    --publisher "${publisher}" --offer "${offer}" --query "[].name" -o tsv)"
  if [[ -n "${sku_filter}" ]] && echo "${skus}" | grep -Eq "${sku_filter}"; then
    echo "${skus}" | grep -E "${sku_filter}" | sort | tail -n 1
  elif echo "${skus}" | grep -q 'byol'; then
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
  if [[ -n "${ISE_SKU}" ]]; then
    ise_sku="${ISE_SKU}"
    if ! az vm image list-skus --location "${LOCATION}" --publisher "${publisher}" \
      --offer "${ise_offer}" --query "[].name" -o tsv | grep -qx "${ise_sku}"; then
      echo "ISE SKU '${ise_sku}' not found in offer ${ise_offer}" >&2
      exit 1
    fi
  else
    ise_sku="$(find_sku "${publisher}" "${ise_offer}" '^cisco-ise')"
  fi
  c8k_sku="$(find_sku "${publisher}" "${c8k_offer}" 'byol')"

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
