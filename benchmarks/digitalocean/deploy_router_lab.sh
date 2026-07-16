#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-amber-router-r20}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INVENTORY_PATH="${INVENTORY_PATH:-${SCRIPT_DIR}/${PREFIX}-inventory.json}"
OBJECT_DIR="${OBJECT_DIR:-/tmp/amber-router-r20-objects}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/agentc_droplets_id_ed25519}"
KNOWN_HOSTS_PATH="${KNOWN_HOSTS_PATH:-/tmp/${PREFIX}-known-hosts}"
RESULT_MANIFEST="${ROOT_DIR}/benchmarks/results/round20_do_binaries_manifest.json"

for path in "${INVENTORY_PATH}" "${OBJECT_DIR}/objects-manifest.json" "${SSH_KEY_PATH}"; do
  if [[ ! -e "${path}" ]]; then
    echo "Required deployment input not found: ${path}" >&2
    exit 1
  fi
done

TARGET_PUBLIC_IP="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).dig("resources", "target", "public_ip")' "${INVENTORY_PATH}")"
LOADGEN_PUBLIC_IP="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).dig("resources", "loadgen", "public_ip")' "${INVENTORY_PATH}")"

touch "${KNOWN_HOSTS_PATH}"
SSH_OPTIONS=(
  -i "${SSH_KEY_PATH}"
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
  -o "UserKnownHostsFile=${KNOWN_HOSTS_PATH}"
)

wait_for_host() {
  local host="$1"
  local label="$2"

  echo "Waiting for ${label} SSH (${host})"
  for _ in $(seq 1 90); do
    if ssh "${SSH_OPTIONS[@]}" "root@${host}" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for ${label} SSH" >&2
  return 1
}

wait_for_host "${TARGET_PUBLIC_IP}" "target"
wait_for_host "${LOADGEN_PUBLIC_IP}" "load generator"

echo "Waiting for target cloud-init"
ssh "${SSH_OPTIONS[@]}" "root@${TARGET_PUBLIC_IP}" cloud-init status --wait
echo "Waiting for load-generator cloud-init"
ssh "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}" cloud-init status --wait

OBJECT_ARCHIVE="/tmp/${PREFIX}-objects.tar.gz"
BINARY_ARCHIVE="/tmp/${PREFIX}-binaries.tar.gz"
tar -czf "${OBJECT_ARCHIVE}" -C "${OBJECT_DIR}" .

ssh "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}" \
  'rm -rf /opt/amber-router/objects && mkdir -p /opt/amber-router/objects'
scp "${SSH_OPTIONS[@]}" "${OBJECT_ARCHIVE}" "root@${LOADGEN_PUBLIC_IP}:/tmp/amber-router-objects.tar.gz"
scp "${SSH_OPTIONS[@]}" "${SCRIPT_DIR}/link_linux_objects.sh" "root@${LOADGEN_PUBLIC_IP}:/tmp/link_linux_objects.sh"
ssh "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}" \
  'tar -xzf /tmp/amber-router-objects.tar.gz -C /opt/amber-router/objects && bash /tmp/link_linux_objects.sh'

ssh "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}" \
  'tar -czf /tmp/amber-router-binaries.tar.gz -C /opt/amber-router bin'
scp "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}:/tmp/amber-router-binaries.tar.gz" "${BINARY_ARCHIVE}"
scp "${SSH_OPTIONS[@]}" "${BINARY_ARCHIVE}" "root@${TARGET_PUBLIC_IP}:/tmp/amber-router-binaries.tar.gz"
ssh "${SSH_OPTIONS[@]}" "root@${TARGET_PUBLIC_IP}" \
  'rm -rf /opt/amber-router/bin && tar -xzf /tmp/amber-router-binaries.tar.gz -C /opt/amber-router && for binary in /opt/amber-router/bin/*; do if [[ -x "${binary}" && -f "${binary}" ]] && ldd "${binary}" | grep -q "not found"; then ldd "${binary}"; exit 1; fi; done'

scp "${SSH_OPTIONS[@]}" \
  "root@${LOADGEN_PUBLIC_IP}:/opt/amber-router/bin/binaries-manifest.json" \
  "${RESULT_MANIFEST}"

echo
echo "Deployment complete."
echo "Target binaries: /opt/amber-router/bin"
echo "Local manifest: ${RESULT_MANIFEST}"
