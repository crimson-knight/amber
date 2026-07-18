#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-amber-db-r23}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DATABASE_DIR="${ROOT_DIR}/benchmarks/database"
INVENTORY_PATH="${INVENTORY_PATH:-${SCRIPT_DIR}/${PREFIX}-inventory.json}"
OBJECT_DIR="${OBJECT_DIR:-/tmp/amber-database-r23-objects}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/agentc_droplets_id_ed25519}"
BOOTSTRAP_USER="${BOOTSTRAP_USER:-amberbench}"
KNOWN_HOSTS_PATH="${KNOWN_HOSTS_PATH:-/tmp/${PREFIX}-known-hosts}"
RESULT_MANIFEST="${RESULT_MANIFEST:-${ROOT_DIR}/benchmarks/results/round23_do_binaries_manifest.json}"
SEED_MANIFEST="${SEED_MANIFEST:-${ROOT_DIR}/benchmarks/results/round23_do_database_seed_manifest.json}"

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
  for _ in $(seq 1 120); do
    if ssh "${SSH_OPTIONS[@]}" "root@${host}" true >/dev/null 2>&1; then
      return 0
    fi
    # DigitalOcean can inherit a first-login expiry when cloud-init updates
    # root. The locked bootstrap account can clear it without a password.
    if ssh "${SSH_OPTIONS[@]}" "${BOOTSTRAP_USER}@${host}" \
      'sudo -n chage -d -1 -E -1 root' >/dev/null 2>&1 && \
      ssh "${SSH_OPTIONS[@]}" "root@${host}" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for ${label} SSH" >&2
  return 1
}

wait_for_host "${TARGET_PUBLIC_IP}" "target"
wait_for_host "${LOADGEN_PUBLIC_IP}" "load generator"
ssh "${SSH_OPTIONS[@]}" "root@${TARGET_PUBLIC_IP}" cloud-init status --wait
ssh "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}" cloud-init status --wait

OBJECT_ARCHIVE="/tmp/${PREFIX}-objects.tar.gz"
BINARY_ARCHIVE="/tmp/${PREFIX}-binaries.tar.gz"
tar -czf "${OBJECT_ARCHIVE}" -C "${OBJECT_DIR}" .

ssh "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}" \
  'rm -rf /opt/amber-database/objects && mkdir -p /opt/amber-database/objects'
scp "${SSH_OPTIONS[@]}" "${OBJECT_ARCHIVE}" "root@${LOADGEN_PUBLIC_IP}:/tmp/amber-database-objects.tar.gz"
scp "${SSH_OPTIONS[@]}" "${SCRIPT_DIR}/link_linux_database_objects.sh" "root@${LOADGEN_PUBLIC_IP}:/tmp/link_linux_database_objects.sh"
ssh "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}" \
  'tar -xzf /tmp/amber-database-objects.tar.gz -C /opt/amber-database/objects && bash /tmp/link_linux_database_objects.sh'

ssh "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}" \
  'tar -czf /tmp/amber-database-binaries.tar.gz -C /opt/amber-database bin'
scp "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}:/tmp/amber-database-binaries.tar.gz" "${BINARY_ARCHIVE}"
scp "${SSH_OPTIONS[@]}" "${BINARY_ARCHIVE}" "root@${TARGET_PUBLIC_IP}:/tmp/amber-database-binaries.tar.gz"
ssh "${SSH_OPTIONS[@]}" "root@${TARGET_PUBLIC_IP}" \
  'rm -rf /opt/amber-database/bin && tar -xzf /tmp/amber-database-binaries.tar.gz -C /opt/amber-database && for binary in /opt/amber-database/bin/*; do if [[ -x "${binary}" && -f "${binary}" ]] && ldd "${binary}" | grep -q "not found"; then ldd "${binary}"; exit 1; fi; done'

scp "${SSH_OPTIONS[@]}" "${DATABASE_DIR}/sql/postgres_schema_seed.sql" "root@${TARGET_PUBLIC_IP}:/opt/amber-database/sql/postgres_schema_seed.sql"
scp "${SSH_OPTIONS[@]}" "${DATABASE_DIR}/sql/sqlite_schema_seed.sql" "root@${TARGET_PUBLIC_IP}:/opt/amber-database/sql/sqlite_schema_seed.sql"
scp "${SSH_OPTIONS[@]}" "${SCRIPT_DIR}/prepare_database_target.sh" "root@${TARGET_PUBLIC_IP}:/tmp/prepare_database_target.sh"
ssh "${SSH_OPTIONS[@]}" "root@${TARGET_PUBLIC_IP}" 'bash /tmp/prepare_database_target.sh'

ssh "${SSH_OPTIONS[@]}" "root@${LOADGEN_PUBLIC_IP}" 'mkdir -p /opt/amber-database/workloads'
for workload in "${DATABASE_DIR}"/wrk/*.lua; do
  scp "${SSH_OPTIONS[@]}" "${workload}" "root@${LOADGEN_PUBLIC_IP}:/opt/amber-database/workloads/$(basename "${workload}")"
done

scp "${SSH_OPTIONS[@]}" \
  "root@${LOADGEN_PUBLIC_IP}:/opt/amber-database/bin/binaries-manifest.json" \
  "${RESULT_MANIFEST}"
scp "${SSH_OPTIONS[@]}" \
  "root@${TARGET_PUBLIC_IP}:/opt/amber-database/results/database-seed-manifest.json" \
  "${SEED_MANIFEST}"

echo
echo "Deployment and million-row seed complete."
echo "Target binaries: /opt/amber-database/bin"
echo "Load scripts: /opt/amber-database/workloads"
echo "Local manifests: ${RESULT_MANIFEST}, ${SEED_MANIFEST}"
