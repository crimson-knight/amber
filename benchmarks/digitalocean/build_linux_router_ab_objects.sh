#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="${ROOT_DIR}/benchmarks/router_revalidation_http_server.cr"
OUT_DIR="${OUT_DIR:-/tmp/amber-router-r21-objects}"
TARGET="${TARGET:-x86_64-unknown-linux-gnu}"
MCPU="${MCPU:-x86-64-v2}"
COMPILER="${COMPILER:-crystal}"

mkdir -p "${OUT_DIR}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd "${COMPILER}"
require_cmd git
require_cmd ruby
require_cmd shasum

build_variant() {
  local name="$1"
  shift

  echo "Cross-compiling ${name} with identical release settings"
  env CRYSTAL_CACHE_DIR="/tmp/amber-router-r21-cache-${name}" \
    "${COMPILER}" build "${SOURCE}" \
      --cross-compile \
      --target "${TARGET}" \
      --mcpu "${MCPU}" \
      --release \
      --no-debug \
      -o "${OUT_DIR}/${name}" \
      "$@" | tee "${OUT_DIR}/${name}.link-command.txt"

  test -f "${OUT_DIR}/${name}.o"
}

# The compile-time router flag is the only intentional binary difference.
build_variant router_legacy -Damber_router_legacy_match
build_variant router_optimized

"${COMPILER}" --version > "${OUT_DIR}/compiler-version.txt"

# shellcheck disable=SC2016
ROOT_DIR="${ROOT_DIR}" OUT_DIR="${OUT_DIR}" TARGET="${TARGET}" MCPU="${MCPU}" ruby -rjson -rdigest -rshellwords -e '
  root = ENV.fetch("ROOT_DIR")
  out = ENV.fetch("OUT_DIR")
  variants = Dir[File.join(out, "*.o")].sort.map do |path|
    name = File.basename(path, ".o")
    {
      "name" => name,
      "object" => File.basename(path),
      "bytes" => File.size(path),
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "router" => name == "router_legacy" ? "legacy split matcher" : "optimized byte-span matcher",
      "compile_flags" => name == "router_legacy" ? "--release --no-debug -Damber_router_legacy_match" : "--release --no-debug",
    }
  end

  manifest = {
    "generated_at_utc" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "source_commit" => `git -C #{Shellwords.escape(root)} rev-parse HEAD`.strip,
    "source" => "benchmarks/router_revalidation_http_server.cr",
    "target" => ENV.fetch("TARGET"),
    "mcpu" => ENV.fetch("MCPU"),
    "compiler" => File.read(File.join(out, "compiler-version.txt")),
    "comparison_invariant" => "same source, compiler, target, release flags, and linker; only amber_router_legacy_match differs",
    "variants" => variants,
  }
  File.write(File.join(out, "objects-manifest.json"), JSON.pretty_generate(manifest))
'

echo
echo "Router A/B objects and manifest written to ${OUT_DIR}"
