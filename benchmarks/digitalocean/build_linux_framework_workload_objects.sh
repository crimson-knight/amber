#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODEC_DIR="${ROOT_DIR}/benchmarks/codec"
SOURCE="${CODEC_DIR}/framework_workload_http_cpu.cr"
OUT_DIR="${OUT_DIR:-/tmp/amber-framework-r22-objects}"
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

if [[ ! -d "${CODEC_DIR}/lib/msgpack" ]]; then
  echo "MessagePack benchmark dependency is missing; run shards install in ${CODEC_DIR}" >&2
  exit 1
fi

build_variant() {
  local name="$1"
  local compiler="$2"
  shift 2

  echo "Cross-compiling ${name} with ${compiler}"
  (
    cd "${CODEC_DIR}"
    env CRYSTAL_CACHE_DIR="/tmp/amber-framework-r22-cache-${name}" \
      "${compiler}" build "${SOURCE}" \
        --cross-compile \
        --target "${TARGET}" \
        --mcpu "${MCPU}" \
        --release \
        --no-debug \
        -o "${OUT_DIR}/${name}" \
        "$@"
  ) | tee "${OUT_DIR}/${name}.link-command.txt"

  test -f "${OUT_DIR}/${name}.o"
}

build_variant stock_json_legacy crystal -Damber_bench_legacy_request_method -Damber_bench_legacy_keep_alive_headers
build_variant stock_json_optimized crystal
build_variant stock_typed_json crystal -Damber_bench_typed_json -Damber_bench_buffer_body
build_variant stock_msgpack_map crystal -Damber_bench_msgpack_map
build_variant stock_msgpack_array crystal -Damber_bench_msgpack_array -Damber_bench_buffer_body
build_variant acrystal_json_optimized acrystal
build_variant acrystal_msgpack_map acrystal -Damber_bench_msgpack_map

crystal --version > "${OUT_DIR}/stock-crystal-version.txt"
acrystal --version > "${OUT_DIR}/acrystal-version.txt"

# shellcheck disable=SC2016
ROOT_DIR="${ROOT_DIR}" OUT_DIR="${OUT_DIR}" TARGET="${TARGET}" MCPU="${MCPU}" ruby -rjson -rdigest -rshellwords -e '
  root = ENV.fetch("ROOT_DIR")
  out = ENV.fetch("OUT_DIR")
  descriptions = {
    "stock_json_legacy" => "legacy Amber JSON params, forced persistence headers, legacy POST method lookup",
    "stock_json_optimized" => "legacy Amber JSON params with round 22 default framework cleanups",
    "stock_typed_json" => "buffered JSON directly into a compile-time typed payload",
    "stock_msgpack_map" => "streaming MessagePack map directly into a compile-time typed payload",
    "stock_msgpack_array" => "buffered compact MessagePack array directly into a compile-time typed payload",
    "acrystal_json_optimized" => "round 22 default JSON path compiled by acrystal",
    "acrystal_msgpack_map" => "typed MessagePack map path compiled by acrystal",
  }
  variants = Dir[File.join(out, "*.o")].sort.map do |path|
    name = File.basename(path, ".o")
    {
      "name" => name,
      "object" => File.basename(path),
      "bytes" => File.size(path),
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "description" => descriptions.fetch(name),
      "link_command" => File.read(File.join(out, "#{name}.link-command.txt")).strip,
    }
  end
  manifest = {
    "generated_at_utc" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "source_commit" => `git -C #{Shellwords.escape(root)} rev-parse HEAD`.strip,
    "source" => "benchmarks/codec/framework_workload_http_cpu.cr",
    "target" => ENV.fetch("TARGET"),
    "mcpu" => ENV.fetch("MCPU"),
    "stock_compiler" => File.read(File.join(out, "stock-crystal-version.txt")),
    "fork_compiler" => File.read(File.join(out, "acrystal-version.txt")),
    "comparison_invariant" => "same source, route table, request sequence, target, release settings, and linker; only named codec/framework/compiler flags differ",
    "variants" => variants,
  }
  File.write(File.join(out, "objects-manifest.json"), JSON.pretty_generate(manifest))
'

echo
echo "Framework workload objects and manifest written to ${OUT_DIR}"
