#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if [[ "$(awk '/SwapTotal/ {print $2}' /proc/meminfo)" == "0" ]]; then
  fallocate -l 1G /swapfile
  chmod 0600 /swapfile
  mkswap /swapfile
  swapon /swapfile
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
  sqlite3 \
  zlib1g

echo "Demo-density target dependencies installed with setup swap active"
