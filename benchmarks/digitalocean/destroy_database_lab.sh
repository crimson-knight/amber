#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-amber-db-r23}"
EXPECTED_CONTEXT="${EXPECTED_CONTEXT:-agentc}"
APPLY="${APPLY:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_PATH="${SCRIPT_DIR}/${PREFIX}-inventory.json"
VPC_NAME="${VPC_NAME:-${PREFIX}-vpc}"

CURRENT_CONTEXT="$(doctl auth list | awk '/\(current\)/ {print $1}')"
if [[ "${CURRENT_CONTEXT}" != "${EXPECTED_CONTEXT}" ]]; then
  echo "Refusing to destroy with doctl context ${CURRENT_CONTEXT:-<none>}; expected ${EXPECTED_CONTEXT}" >&2
  exit 1
fi

echo "DigitalOcean resources selected for deletion:"
echo "  ${PREFIX}-target"
echo "  ${PREFIX}-loadgen"
echo "  ${VPC_NAME}"

if [[ "${APPLY}" != "1" ]]; then
  echo
  echo "Dry run only. Rerun with APPLY=1 to destroy these exact resources."
  exit 0
fi

for name in "${PREFIX}-target" "${PREFIX}-loadgen"; do
  if doctl compute droplet get "${name}" >/dev/null 2>&1; then
    echo "Deleting ${name}"
    doctl compute droplet delete --force "${name}"
  else
    echo "Droplet not found, skipping: ${name}"
  fi
done

for _ in $(seq 1 60); do
  remaining=0
  for name in "${PREFIX}-target" "${PREFIX}-loadgen"; do
    if doctl compute droplet get "${name}" >/dev/null 2>&1; then
      remaining=1
    fi
  done
  [[ "${remaining}" -eq 0 ]] && break
  sleep 2
done

VPC_UUID="$(doctl vpcs list --output json | VPC_NAME="${VPC_NAME}" ruby -rjson -e '
  vpc = JSON.parse(STDIN.read).find { |row| row["name"] == ENV.fetch("VPC_NAME") }
  puts vpc["id"] if vpc
')"

if [[ -n "${VPC_UUID}" ]]; then
  echo "Deleting VPC ${VPC_NAME}"
  doctl vpcs delete --force "${VPC_UUID}"
fi

if [[ -f "${INVENTORY_PATH}" ]]; then
  INVENTORY_PATH="${INVENTORY_PATH}" ruby -rjson -e '
    path = ENV.fetch("INVENTORY_PATH")
    payload = JSON.parse(File.read(path))
    payload["destroyed_at_utc"] = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    File.write(path, JSON.pretty_generate(payload))
  '
fi

echo "Destroy complete."
