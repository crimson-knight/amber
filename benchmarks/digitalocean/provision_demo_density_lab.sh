#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-amber-density-r24}"
EXPECTED_CONTEXT="${EXPECTED_CONTEXT:-agentc}"
REGION="${REGION:-nyc3}"
IMAGE="${IMAGE:-ubuntu-24-04-x64}"
TARGET_SPECS="${TARGET_SPECS:-micro=s-1vcpu-512mb-10gb:shared,shared2x4=s-2vcpu-4gb:shared,dedicated2x4=c-2:dedicated}"
LOADGEN_SIZE="${LOADGEN_SIZE:-c-4}"
VPC_NAME="${VPC_NAME:-${PREFIX}-vpc}"
VPC_RANGE="${VPC_RANGE:-10.142.0.0/20}"
SSH_PUBLIC_KEY_PATH="${SSH_PUBLIC_KEY_PATH:-${HOME}/.ssh/agentc_droplets_id_ed25519.pub}"
APPLY="${APPLY:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_PATH="${INVENTORY_PATH:-${SCRIPT_DIR}/${PREFIX}-inventory.json}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

for command in doctl ruby ssh-keygen; do
  require_cmd "${command}"
done

if [[ ! -f "${SSH_PUBLIC_KEY_PATH}" ]]; then
  echo "SSH public key not found: ${SSH_PUBLIC_KEY_PATH}" >&2
  exit 1
fi

CURRENT_CONTEXT="$(doctl auth list | awk '/\(current\)/ {print $1}')"
if [[ "${CURRENT_CONTEXT}" != "${EXPECTED_CONTEXT}" ]]; then
  echo "Refusing to provision with doctl context ${CURRENT_CONTEXT:-<none>}; expected ${EXPECTED_CONTEXT}" >&2
  exit 1
fi

SSH_PUBLIC_KEY="$(<"${SSH_PUBLIC_KEY_PATH}")"
SSH_FINGERPRINT="$(ssh-keygen -lf "${SSH_PUBLIC_KEY_PATH}" | awk '{print $2}')"

validate_target_specs() {
  local entry label remainder size cpu_class
  IFS=',' read -r -a entries <<< "${TARGET_SPECS}"
  for entry in "${entries[@]}"; do
    label="${entry%%=*}"
    remainder="${entry#*=}"
    size="${remainder%%:*}"
    cpu_class="${remainder#*:}"
    if [[ ! "${label}" =~ ^[a-z0-9_]+$ ]] || [[ -z "${size}" ]] || [[ ! "${cpu_class}" =~ ^(shared|dedicated)$ ]]; then
      echo "Invalid target spec: ${entry}; expected label=size:shared|dedicated" >&2
      exit 1
    fi
  done
}

validate_target_specs

print_plan() {
  echo "DigitalOcean Amber demo-density lab plan"
  echo "-----------------------------------------"
  echo "context:         ${CURRENT_CONTEXT}"
  echo "prefix:          ${PREFIX}"
  echo "region:          ${REGION}"
  echo "image:           ${IMAGE}"
  echo "vpc:             ${VPC_NAME} (${VPC_RANGE})"
  echo "targets:"
  IFS=',' read -r -a entries <<< "${TARGET_SPECS}"
  for entry in "${entries[@]}"; do
    echo "  ${PREFIX}-${entry%%=*}: ${entry#*=}"
  done
  echo "load generator:  ${PREFIX}-loadgen (${LOADGEN_SIZE})"
  echo "ssh fingerprint: ${SSH_FINGERPRINT}"
  echo "inventory:       ${INVENTORY_PATH}"
  echo
  echo "This creates all targets together in one VPC so plan comparisons see the"
  echo "same regional conditions. Rerun with APPLY=1 to create the isolated lab."
}

if [[ "${APPLY}" != "1" ]]; then
  print_plan
  exit 0
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
    --description "Short-lived Amber shared-vs-dedicated demo density lab" \
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
  - name: amberbench
    groups: [sudo]
    shell: /bin/bash
    lock_passwd: true
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}
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

  if [[ "${role}" == "loadgen" ]]; then
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
  - zlib1g-dev
EOF
  fi

  cat <<EOF
runcmd:
  - chage -d "\$(date -I)" -E -1 root
  - mkdir -p /opt/amber-density/bin /opt/amber-density/load /opt/amber-density/objects /opt/amber-density/results /opt/amber-density/seed /opt/amber-density/sql
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow 22/tcp
  - ufw allow from ${VPC_RANGE} to any port 42000:42063 proto tcp
  - ufw --force enable
EOF
}

create_droplet() {
  local name="$1"
  local size="$2"
  local role="$3"
  local user_data_file="/tmp/${name}.user-data.yml"

  if doctl compute droplet get "${name}" >/dev/null 2>&1; then
    echo "Droplet already exists; refusing partial duplicate: ${name}" >&2
    exit 1
  fi
  render_user_data "${role}" > "${user_data_file}"
  echo "Creating ${name} (${size})"
  doctl compute droplet create "${name}" \
    --size "${size}" \
    --image "${IMAGE}" \
    --region "${REGION}" \
    --project-id "${PROJECT_ID}" \
    --vpc-uuid "${VPC_UUID}" \
    --droplet-agent=false \
    --tag-names "amber-benchmark,${PREFIX},amber-density-benchmark-${role}" \
    --user-data-file "${user_data_file}" \
    --wait >/dev/null
}

IFS=',' read -r -a entries <<< "${TARGET_SPECS}"
for entry in "${entries[@]}"; do
  label="${entry%%=*}"
  remainder="${entry#*=}"
  size="${remainder%%:*}"
  create_droplet "${PREFIX}-${label}" "${size}" "target"
done
create_droplet "${PREFIX}-loadgen" "${LOADGEN_SIZE}" "loadgen"

PREFIX="${PREFIX}" TARGET_SPECS="${TARGET_SPECS}" VPC_UUID="${VPC_UUID}" \
VPC_NAME="${VPC_NAME}" VPC_RANGE="${VPC_RANGE}" REGION="${REGION}" \
INVENTORY_PATH="${INVENTORY_PATH}" SSH_FINGERPRINT="${SSH_FINGERPRINT}" \
ruby -rjson -ropen3 -e '
  prefix = ENV.fetch("PREFIX")
  size_json, size_status = Open3.capture2("doctl", "compute", "size", "list", "--output", "json")
  abort("Unable to fetch DigitalOcean sizes") unless size_status.success?
  sizes = JSON.parse(size_json).to_h { |row| [row.fetch("slug"), row] }

  fetch_droplet = lambda do |name|
    json, status = Open3.capture2("doctl", "compute", "droplet", "get", name, "--output", "json")
    abort("Unable to fetch #{name}") unless status.success?
    row = JSON.parse(json)
    row = row.first if row.is_a?(Array)
    networks = Array(row.dig("networks", "v4"))
    {
      "id" => row.fetch("id"),
      "name" => name,
      "public_ip" => networks.find { |network| network["type"] == "public" }&.fetch("ip_address"),
      "private_ip" => networks.find { |network| network["type"] == "private" }&.fetch("ip_address"),
      "size" => row.fetch("size_slug"),
      "region" => row.dig("region", "slug"),
    }
  end

  targets = ENV.fetch("TARGET_SPECS").split(",").map do |spec|
    label, remainder = spec.split("=", 2)
    size, cpu_class = remainder.split(":", 2)
    plan = sizes.fetch(size)
    fetch_droplet.call("#{prefix}-#{label}").merge(
      "label" => label,
      "cpu_class" => cpu_class,
      "vcpus" => plan.fetch("vcpus"),
      "memory_mb" => plan.fetch("memory"),
      "disk_gb" => plan.fetch("disk"),
      "price_monthly" => plan.fetch("price_monthly"),
      "price_hourly" => plan.fetch("price_hourly")
    )
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
    "resources" => {
      "targets" => targets,
      "loadgen" => fetch_droplet.call("#{prefix}-loadgen").merge("plan" => sizes.fetch(fetch_droplet.call("#{prefix}-loadgen").fetch("size"))),
    },
  }
  File.write(ENV.fetch("INVENTORY_PATH"), JSON.pretty_generate(payload))
'

echo
echo "Lab created: ${INVENTORY_PATH}"
echo "Wait for cloud-init before deployment."
