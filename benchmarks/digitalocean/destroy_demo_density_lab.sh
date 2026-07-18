#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-amber-density-r24}"
EXPECTED_CONTEXT="${EXPECTED_CONTEXT:-agentc}"
APPLY="${APPLY:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_PATH="${INVENTORY_PATH:-${SCRIPT_DIR}/${PREFIX}-inventory.json}"
VPC_NAME="${VPC_NAME:-${PREFIX}-vpc}"

CURRENT_CONTEXT="$(doctl auth list | awk '/\(current\)/ {print $1}')"
if [[ "${CURRENT_CONTEXT}" != "${EXPECTED_CONTEXT}" ]]; then
  echo "Refusing to destroy with doctl context ${CURRENT_CONTEXT:-<none>}; expected ${EXPECTED_CONTEXT}" >&2
  exit 1
fi
if [[ ! -f "${INVENTORY_PATH}" ]]; then
  echo "Inventory not found; refusing name-based deletion: ${INVENTORY_PATH}" >&2
  exit 1
fi

RESOURCE_NAMES="$(ruby -rjson -e '
  payload = JSON.parse(File.read(ARGV.fetch(0)))
  payload.dig("resources", "targets").each { |target| puts target.fetch("name") }
  puts payload.dig("resources", "loadgen", "name")
' "${INVENTORY_PATH}")"
VPC_UUID="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).dig("vpc", "id")' "${INVENTORY_PATH}")"

echo "DigitalOcean resources selected for deletion:"
while IFS= read -r name; do
  echo "  ${name}"
done <<< "${RESOURCE_NAMES}"
echo "  ${VPC_NAME} (${VPC_UUID})"

if [[ "${APPLY}" != "1" ]]; then
  echo
  echo "Dry run only. Rerun with APPLY=1 to destroy these exact resources."
  exit 0
fi

while IFS= read -r name; do
  if doctl compute droplet get "${name}" >/dev/null 2>&1; then
    echo "Deleting ${name}"
    doctl compute droplet delete --force "${name}"
  else
    echo "Droplet not found, skipping: ${name}"
  fi
done <<< "${RESOURCE_NAMES}"

for _ in $(seq 1 90); do
  remaining=0
  while IFS= read -r name; do
    if doctl compute droplet get "${name}" >/dev/null 2>&1; then
      remaining=1
    fi
  done <<< "${RESOURCE_NAMES}"
  [[ "${remaining}" -eq 0 ]] && break
  sleep 2
done

if doctl vpcs get "${VPC_UUID}" >/dev/null 2>&1; then
  echo "Deleting VPC ${VPC_NAME}"
  doctl vpcs delete --force "${VPC_UUID}"
fi

INVENTORY_PATH="${INVENTORY_PATH}" ruby -rjson -e '
  path = ENV.fetch("INVENTORY_PATH")
  payload = JSON.parse(File.read(path))
  payload["destroyed_at_utc"] = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  File.write(path, JSON.pretty_generate(payload))
'

echo "Destroy complete."
