#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-amber-db-r23}"
EXPECTED_CONTEXT="${EXPECTED_CONTEXT:-agentc}"
REGION="${REGION:-nyc3}"
IMAGE="${IMAGE:-ubuntu-24-04-x64}"
TARGET_SIZE="${TARGET_SIZE:-s-1vcpu-512mb-10gb}"
LOADGEN_SIZE="${LOADGEN_SIZE:-c-4}"
VPC_NAME="${VPC_NAME:-${PREFIX}-vpc}"
VPC_RANGE="${VPC_RANGE:-10.141.0.0/20}"
SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH:-${HOME}/.ssh/agentc_droplets_id_ed25519.pub}"
APPLY="${APPLY:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_PATH="${SCRIPT_DIR}/${PREFIX}-inventory.json"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd doctl
require_cmd ruby
require_cmd ssh-keygen

if [[ ! -f "${SSH_PUBLIC_KEY_PATH}" ]]; then
  echo "SSH public key not found: ${SSH_PUBLIC_KEY_PATH}" >&2
  exit 1
fi

CURRENT_CONTEXT="$(doctl auth list | awk '/\(current\)/ {print $1}')"
if [[ "${CURRENT_CONTEXT}" != "${EXPECTED_CONTEXT}" ]]; then
  echo "Refusing to provision with doctl context ${CURRENT_CONTEXT:-<none>}; expected ${EXPECTED_CONTEXT}" >&2
  exit 1
fi

SSH_PUBLIC_KEY="$(cat "${SSH_PUBLIC_KEY_PATH}")"
SSH_FINGERPRINT="$(ssh-keygen -lf "${SSH_PUBLIC_KEY_PATH}" | awk '{print $2}')"

print_plan() {
  cat <<EOF
DigitalOcean Amber database lab plan
------------------------------------
context:         ${CURRENT_CONTEXT}
prefix:          ${PREFIX}
region:          ${REGION}
image:           ${IMAGE}
vpc:             ${VPC_NAME} (${VPC_RANGE})
target:          ${PREFIX}-target (${TARGET_SIZE})
load generator:  ${PREFIX}-loadgen (${LOADGEN_SIZE})
ssh fingerprint: ${SSH_FINGERPRINT}
inventory:       ${INVENTORY_PATH}

The target receives PostgreSQL, SQLite, runtime libraries, fio, and telemetry
tools. A temporary setup swapfile is disabled after the million-row databases
are seeded. The load generator receives linker libraries and wrk.

To create the isolated lab, rerun with APPLY=1.
EOF
}

if [[ "${APPLY}" != "1" ]]; then
  print_plan
  exit 0
fi

if doctl compute droplet get "${PREFIX}-target" >/dev/null 2>&1 || \
   doctl compute droplet get "${PREFIX}-loadgen" >/dev/null 2>&1; then
  echo "A droplet with this lab prefix already exists; refusing to create a partial duplicate." >&2
  exit 1
fi

PROJECT_ID="$(doctl projects list --output json | ruby -rjson -e '
  project = JSON.parse(STDIN.read).find { |row| row["is_default"] }
  abort("No default DigitalOcean project found") unless project
  puts project.fetch("id")
')"

VPC_UUID="$(doctl vpcs list --output json | VPC_NAME="${VPC_NAME}" ruby -rjson -e '
  vpc = JSON.parse(STDIN.read).find { |row| row["name"] == ENV.fetch("VPC_NAME") }
  puts vpc["id"] if vpc
')"

if [[ -z "${VPC_UUID}" ]]; then
  echo "Creating isolated VPC ${VPC_NAME}"
  VPC_UUID="$(doctl vpcs create \
    --name "${VPC_NAME}" \
    --region "${REGION}" \
    --ip-range "${VPC_RANGE}" \
    --description "Short-lived Amber same-host database performance lab" \
    --output json | ruby -rjson -e '
      row = JSON.parse(STDIN.read)
      row = row.first if row.is_a?(Array)
      puts row.fetch("id")
    ')"
fi

render_user_data() {
  local role="$1"

  cat <<EOF
#cloud-config
users:
  - default
  - name: root
    lock_passwd: true
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}
ssh_pwauth: false
package_update: true
package_upgrade: false
packages:
  - ca-certificates
  - curl
  - jq
  - procps
  - ruby
  - sysstat
  - time
  - ufw
EOF

  if [[ "${role}" == "target" ]]; then
    cat <<'EOF'
  - fio
  - libgc1
  - libpcre2-8-0
  - libpq5
  - libsqlite3-0
  - libssl3t64
  - libxml2
  - libyaml-0-2
  - postgresql
  - postgresql-client
  - sqlite3
  - zlib1g
EOF
  else
    cat <<'EOF'
  - build-essential
  - libgc-dev
  - libpcre2-dev
  - libpq-dev
  - libsqlite3-dev
  - libssl-dev
  - libxml2-dev
  - libyaml-dev
  - lld
  - pkg-config
  - wrk
  - zlib1g-dev
EOF
  fi

  cat <<EOF
runcmd:
  # Re-declaring root can inherit DigitalOcean's first-login password expiry.
  # Keep password auth locked, but clear the expiry so SSH-key automation works.
  - chage -d -1 -E -1 root
  - mkdir -p /opt/amber-database/bin /opt/amber-database/data /opt/amber-database/objects /opt/amber-database/results /opt/amber-database/sql /opt/amber-database/workloads
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw allow from ${VPC_RANGE} to any port 41023 proto tcp
  - ufw --force enable
EOF

  if [[ "${role}" == "target" ]]; then
    cat <<'EOF'
  - fallocate -l 1G /swapfile
  - chmod 0600 /swapfile
  - mkswap /swapfile
  - swapon /swapfile
EOF
  fi
}

create_droplet() {
  local name="$1"
  local size="$2"
  local role="$3"
  local user_data_file="${SCRIPT_DIR}/${name}.user-data.yml"

  render_user_data "${role}" > "${user_data_file}"
  echo "Creating ${name} (${size})"
  doctl compute droplet create "${name}" \
    --size "${size}" \
    --image "${IMAGE}" \
    --region "${REGION}" \
    --project-id "${PROJECT_ID}" \
    --vpc-uuid "${VPC_UUID}" \
    --droplet-agent=false \
    --tag-names "amber-benchmark,${PREFIX},amber-database-benchmark-${role}" \
    --user-data-file "${user_data_file}" \
    --wait >/dev/null
}

create_droplet "${PREFIX}-target" "${TARGET_SIZE}" "target"
create_droplet "${PREFIX}-loadgen" "${LOADGEN_SIZE}" "loadgen"

PREFIX="${PREFIX}" VPC_UUID="${VPC_UUID}" VPC_NAME="${VPC_NAME}" VPC_RANGE="${VPC_RANGE}" \
REGION="${REGION}" INVENTORY_PATH="${INVENTORY_PATH}" SSH_FINGERPRINT="${SSH_FINGERPRINT}" \
ruby -rjson -ropen3 -e '
  prefix = ENV.fetch("PREFIX")
  resources = {}
  %w[target loadgen].each do |role|
    name = "#{prefix}-#{role}"
    json, status = Open3.capture2("doctl", "compute", "droplet", "get", name, "--output", "json")
    abort("Unable to fetch #{name}") unless status.success?
    droplet = JSON.parse(json)
    droplet = droplet.first if droplet.is_a?(Array)
    networks = Array(droplet.dig("networks", "v4"))
    resources[role] = {
      "id" => droplet.fetch("id"),
      "name" => name,
      "public_ip" => networks.find { |row| row["type"] == "public" }&.fetch("ip_address"),
      "private_ip" => networks.find { |row| row["type"] == "private" }&.fetch("ip_address"),
      "size" => droplet.fetch("size_slug"),
      "region" => droplet.dig("region", "slug"),
    }
  end
  payload = {
    "created_at_utc" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "prefix" => prefix,
    "region" => ENV.fetch("REGION"),
    "vpc" => {
      "id" => ENV.fetch("VPC_UUID"),
      "name" => ENV.fetch("VPC_NAME"),
      "ip_range" => ENV.fetch("VPC_RANGE"),
    },
    "ssh_fingerprint" => ENV.fetch("SSH_FINGERPRINT"),
    "resources" => resources,
  }
  File.write(ENV.fetch("INVENTORY_PATH"), JSON.pretty_generate(payload))
'

echo
echo "Lab created: ${INVENTORY_PATH}"
echo "Wait for cloud-init on both hosts before deployment."
