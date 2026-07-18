#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-amber-density-r24}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DATABASE_DIR="${ROOT_DIR}/benchmarks/database"
INVENTORY_PATH="${INVENTORY_PATH:-${SCRIPT_DIR}/${PREFIX}-inventory.json}"
OBJECT_DIR="${OBJECT_DIR:-/tmp/amber-database-r23-objects}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/agentc_droplets_id_ed25519}"
BOOTSTRAP_USER="${BOOTSTRAP_USER:-amberbench}"
KNOWN_HOSTS_PATH="${KNOWN_HOSTS_PATH:-/tmp/${PREFIX}-known-hosts}"
RESULT_MANIFEST="${RESULT_MANIFEST:-${ROOT_DIR}/benchmarks/results/round24_do_binaries_manifest.json}"

for path in "${INVENTORY_PATH}" "${OBJECT_DIR}/objects-manifest.json" "${SSH_KEY_PATH}"; do
  if [[ ! -e "${path}" ]]; then
    echo "Required deployment input not found: ${path}" >&2
    exit 1
  fi
done

LOADGEN_PUBLIC_IP="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).dig("resources", "loadgen", "public_ip")' "${INVENTORY_PATH}")"
TARGET_ROWS="$(ruby -rjson -e '
  JSON.parse(File.read(ARGV.fetch(0))).dig("resources", "targets").each do |target|
    puts [target.fetch("label"), target.fetch("public_ip"), target.fetch("private_ip")].join("\t")
  end
' "${INVENTORY_PATH}")"

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
  for _ in $(seq 1 120); do
    if ssh -n "${SSH_OPTIONS[@]}" "root@${host}" true >/dev/null 2>&1; then
      return 0
    fi
    if ssh -n "${SSH_OPTIONS[@]}" "${BOOTSTRAP_USER}@${host}" \
      'sudo -n chage -d "$(date -I)" -E -1 root' >/dev/null 2>&1 && \
      ssh -n "${SSH_OPTIONS[@]}" "root@${host}" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for ${label} SSH" >&2
  return 1
}

wait_for_host "${LOADGEN_PUBLIC_IP}" "load generator"
while IFS=$'\t' read -r label public_ip _private_ip; do
  wait_for_host "${public_ip}" "${label} target"
done <<< "${TARGET_ROWS}"

ssh -n "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}" cloud-init status --wait
while IFS=$'\t' read -r _label public_ip _private_ip; do
  ssh -n "${SSH_OPTIONS[@]}" "root@${public_ip}" cloud-init status --wait
done <<< "${TARGET_ROWS}"

OBJECT_ARCHIVE="/tmp/${PREFIX}-objects.tar.gz"
tar -czf "${OBJECT_ARCHIVE}" -C "${OBJECT_DIR}" .
ssh -n "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}" \
  'rm -rf /opt/amber-density/objects /opt/amber-density/bin && mkdir -p /opt/amber-density/objects /opt/amber-density/bin'
scp "${SSH_OPTIONS[@]}" "${OBJECT_ARCHIVE}" "root@${LOADGEN_PUBLIC_IP}:/tmp/amber-density-objects.tar.gz"
scp "${SSH_OPTIONS[@]}" "${SCRIPT_DIR}/link_linux_database_objects.sh" "root@${LOADGEN_PUBLIC_IP}:/tmp/link_linux_database_objects.sh"
ssh -n "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}" \
  'tar -xzf /tmp/amber-density-objects.tar.gz -C /opt/amber-density/objects && bash /tmp/link_linux_database_objects.sh /opt/amber-density/objects /opt/amber-density/bin'

scp "${SSH_OPTIONS[@]}" \
  "${ROOT_DIR}/benchmarks/bin/demo_density_fixed_rate.rb" \
  "root@${LOADGEN_PUBLIC_IP}:/opt/amber-density/load/demo_density_fixed_rate.rb"
ssh -n "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}" \
  'chmod 0755 /opt/amber-density/load/demo_density_fixed_rate.rb'
scp "${SSH_OPTIONS[@]}" \
  "root@${LOADGEN_PUBLIC_IP}:/opt/amber-density/bin/binaries-manifest.json" \
  "${RESULT_MANIFEST}"
LOCAL_BINARY="/tmp/${PREFIX}-stock_sqlite"
scp "${SSH_OPTIONS[@]}" \
  "root@${LOADGEN_PUBLIC_IP}:/opt/amber-density/bin/stock_sqlite" \
  "${LOCAL_BINARY}"

while IFS=$'\t' read -r label public_ip _private_ip; do
  echo "Preparing ${label} target"
  scp "${SSH_OPTIONS[@]}" \
    "${SCRIPT_DIR}/install_demo_density_target_dependencies.sh" \
    "root@${public_ip}:/tmp/install_demo_density_target_dependencies.sh"
  ssh -n "${SSH_OPTIONS[@]}" "root@${public_ip}" \
    'bash /tmp/install_demo_density_target_dependencies.sh'

  scp "${SSH_OPTIONS[@]}" \
    "${LOCAL_BINARY}" \
    "root@${public_ip}:/opt/amber-density/bin/stock_sqlite"
  ssh -n "${SSH_OPTIONS[@]}" "root@${public_ip}" \
    'chmod 0755 /opt/amber-density/bin/stock_sqlite && ! ldd /opt/amber-density/bin/stock_sqlite | grep -q "not found"'

  scp "${SSH_OPTIONS[@]}" \
    "${DATABASE_DIR}/sql/sqlite_schema_seed.sql" \
    "root@${public_ip}:/opt/amber-density/sql/sqlite_schema_seed.sql"
  scp "${SSH_OPTIONS[@]}" \
    "${SCRIPT_DIR}/prepare_demo_density_target.sh" \
    "root@${public_ip}:/tmp/prepare_demo_density_target.sh"
  ssh -n "${SSH_OPTIONS[@]}" "root@${public_ip}" \
    'bash /tmp/prepare_demo_density_target.sh'

  scp "${SSH_OPTIONS[@]}" \
    "root@${public_ip}:/opt/amber-density/results/seed-manifest.json" \
    "${ROOT_DIR}/benchmarks/results/round24_${label}_seed_manifest.json"
done <<< "${TARGET_ROWS}"

echo
echo "Demo-density deployment complete."
echo "Binary: /opt/amber-density/bin/stock_sqlite"
echo "Load generator: /opt/amber-density/load/demo_density_fixed_rate.rb"
