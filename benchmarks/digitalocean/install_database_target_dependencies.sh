#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if [[ "$(awk '/SwapTotal/ {print $2}' /proc/meminfo)" == "0" ]]; then
  echo "Setup swap must be active before installing target packages" >&2
  exit 1
fi

apt-get update
apt-get install --yes --no-install-recommends \
  fio \
  libgc1 \
  libpcre2-8-0 \
  libpq5 \
  libsqlite3-0 \
  libssl3t64 \
  libxml2 \
  libyaml-0-2 \
  postgresql \
  postgresql-client \
  sqlite3 \
  zlib1g

systemctl enable --now postgresql

echo "Target database dependencies installed with setup swap active"
