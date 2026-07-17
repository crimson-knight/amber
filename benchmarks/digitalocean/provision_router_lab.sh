#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-amber-router-r20}"
EXPECTED_CONTEXT="${EXPECTED_CONTEXT:-agentc}"
REGION="${REGION:-nyc3}"
IMAGE="${IMAGE:-ubuntu-24-04-x64}"
TARGET_SIZE="${TARGET_SIZE:-s-1vcpu-512mb-10gb}"
LOADGEN_SIZE="${LOADGEN_SIZE:-c-4}"
VPC_NAME="${VPC_NAME:-${PREFIX}-vpc}"
VPC_RANGE="${VPC_RANGE:-10.140.0.0/20}"
SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH:-${HOME}/.ssh/agentc_droplets_id_ed25519.pub}"
APPLY="${APPLY:-0}"
OHA_URL="https://github.com/hatoo/oha/releases/download/v1.14.0/oha-linux-amd64"
OHA_SHA256="6fc16b5f9901fd2266b1a2b49b1689f76f91ddc7c96f2d0d08b161a870f7ef18"

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
DigitalOcean Amber router lab plan
----------------------------------
context:         ${CURRENT_CONTEXT}
prefix:          ${PREFIX}
region:          ${REGION}
image:           ${IMAGE}
vpc:             ${VPC_NAME} (${VPC_RANGE})
target:          ${PREFIX}-target (${TARGET_SIZE}, \$0.00595/hour)
load generator:  ${PREFIX}-loadgen (${LOADGEN_SIZE}, \$0.125/hour)
ssh fingerprint: ${SSH_FINGERPRINT}
inventory:       ${INVENTORY_PATH}

The target receives runtime libraries only. The load generator receives linker
libraries and the SHA-256-verified oha 1.14.0 binary.

To create the lab, rerun with APPLY=1.
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
    --description "Short-lived Amber router performance lab" \
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
bootcmd:
  - chage -d -1 -E -1 -M 99999 root
package_update: true
package_upgrade: false
packages:
  - ca-certificates
  - curl
  - jq
  - sysstat
  - time
  - ufw
EOF

  if [[ "${role}" == "target" ]]; then
    cat <<'EOF'
  - libgc1
  - libpcre2-8-0
  - libssl3t64
  - libxml2
  - libyaml-0-2
  - zlib1g
EOF
  else
    cat <<'EOF'
  - build-essential
  - libgc-dev
  - libpcre2-dev
  - libssl-dev
  - libxml2-dev
  - libyaml-dev
  - lld
  - pkg-config
  - zlib1g-dev
EOF
  fi

  cat <<EOF
runcmd:
  - mkdir -p /opt/amber-router/bin /opt/amber-router/objects /opt/amber-router/results
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw allow from ${VPC_RANGE} to any port 41019 proto tcp
  - ufw --force enable
EOF

  if [[ "${role}" == "loadgen" ]]; then
    cat <<EOF
  - curl -fsSL ${OHA_URL} -o /usr/local/bin/oha
  - echo '${OHA_SHA256}  /usr/local/bin/oha' | sha256sum -c -
  - chmod 0755 /usr/local/bin/oha
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
    --tag-names "amber-benchmark,${PREFIX},amber-benchmark-${role}" \
    --user-data-file "${user_data_file}" \
    --wait >/dev/null
}

create_droplet "${PREFIX}-target" "${TARGET_SIZE}" "target"
create_droplet "${PREFIX}-loadgen" "${LOADGEN_SIZE}" "loadgen"

PREFIX="${PREFIX}" VPC_UUID="${VPC_UUID}" VPC_NAME="${VPC_NAME}" VPC_RANGE="${VPC_RANGE}" \
REGION="${REGION}" INVENTORY_PATH="${INVENTORY_PATH}" SSH_FINGERPRINT="${SSH_FINGERPRINT}" \
ruby -rjson -ropen3 -e '
  prefix = ENV.fetch("PREFIX")
  roles = %w[target loadgen]
  resources = {}

  roles.each do |role|
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
