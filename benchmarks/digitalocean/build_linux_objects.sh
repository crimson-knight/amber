#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="${ROOT_DIR}/benchmarks/router_revalidation_http_server.cr"
OUT_DIR="${OUT_DIR:-/tmp/amber-router-r20-objects}"
TARGET="${TARGET:-x86_64-unknown-linux-gnu}"
MCPU="${MCPU:-x86-64-v2}"

mkdir -p "${OUT_DIR}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd crystal
require_cmd acrystal
require_cmd git
require_cmd ruby
require_cmd shasum

build_variant() {
  local name="$1"
  local compiler="$2"
  shift 2

  echo "Cross-compiling ${name} with ${compiler}"
  env CRYSTAL_CACHE_DIR="/tmp/amber-router-r20-cache-${name}" \
    "${compiler}" build "${SOURCE}" \
      --cross-compile \
      --target "${TARGET}" \
      --mcpu "${MCPU}" \
      -o "${OUT_DIR}/${name}" \
      "$@" | tee "${OUT_DIR}/${name}.link-command.txt"

  test -f "${OUT_DIR}/${name}.o"
}

build_variant stock_default crystal
build_variant stock_o3_multi crystal -O3 --no-debug
build_variant stock_release crystal --release --no-debug
build_variant stock_release_legacy crystal --release --no-debug -Damber_router_legacy_match
build_variant acrystal_release acrystal --release --no-debug

crystal --version > "${OUT_DIR}/stock-crystal-version.txt"
acrystal --version > "${OUT_DIR}/acrystal-version.txt"

# shellcheck disable=SC2016
ROOT_DIR="${ROOT_DIR}" OUT_DIR="${OUT_DIR}" TARGET="${TARGET}" MCPU="${MCPU}" ruby -rjson -rdigest -e '
  root = ENV.fetch("ROOT_DIR")
  out = ENV.fetch("OUT_DIR")
  variants = Dir[File.join(out, "*.o")].sort.map do |path|
    {
      "name" => File.basename(path, ".o"),
      "object" => File.basename(path),
      "bytes" => File.size(path),
      "sha256" => Digest::SHA256.file(path).hexdigest,
    }
  end

  manifest = {
    "generated_at_utc" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "source_commit" => `git -C #{Shellwords.escape(root)} rev-parse HEAD`.strip,
    "target" => ENV.fetch("TARGET"),
    "mcpu" => ENV.fetch("MCPU"),
    "stock_compiler" => File.read(File.join(out, "stock-crystal-version.txt")),
    "fork_compiler" => File.read(File.join(out, "acrystal-version.txt")),
    "variants" => variants,
  }
  File.write(File.join(out, "objects-manifest.json"), JSON.pretty_generate(manifest))
' -rshellwords

echo
echo "Objects and manifest written to ${OUT_DIR}"
