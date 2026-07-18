#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATABASE_DIR="${ROOT_DIR}/benchmarks/database"
SOURCE="${DATABASE_DIR}/src/server.cr"
OUT_DIR="${OUT_DIR:-/tmp/amber-database-r23-objects}"
TARGET="${TARGET:-x86_64-unknown-linux-gnu}"
MCPU="${MCPU:-x86-64-v2}"

mkdir -p "${OUT_DIR}"

for command in crystal acrystal git ruby; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Missing required command: ${command}" >&2
    exit 1
  }
done

for dependency in grant db pg sqlite3; do
  if [[ ! -d "${DATABASE_DIR}/lib/${dependency}" ]]; then
    echo "Missing ${dependency}; run shards install in ${DATABASE_DIR}" >&2
    exit 1
  fi
done

build_variant() {
  local name="$1"
  local compiler="$2"
  local database_flag="$3"

  echo "Cross-compiling ${name} with ${compiler}"
  (
    cd "${DATABASE_DIR}"
    env CRYSTAL_CACHE_DIR="/tmp/amber-database-r23-cache-${name}" \
      "${compiler}" build "${SOURCE}" \
        --cross-compile \
        --target "${TARGET}" \
        --mcpu "${MCPU}" \
        --release \
        --no-debug \
        -D"${database_flag}" \
        -o "${OUT_DIR}/${name}"
  ) | tee "${OUT_DIR}/${name}.link-command.txt"

  test -f "${OUT_DIR}/${name}.o"
}

build_variant stock_postgres crystal db_postgres
build_variant stock_sqlite crystal db_sqlite
build_variant acrystal_postgres acrystal db_postgres
build_variant acrystal_sqlite acrystal db_sqlite

crystal --version > "${OUT_DIR}/stock-crystal-version.txt"
acrystal --version > "${OUT_DIR}/acrystal-version.txt"

# shellcheck disable=SC2016,SC2269
ROOT_DIR="${ROOT_DIR}" DATABASE_DIR="${DATABASE_DIR}" OUT_DIR="${OUT_DIR}" TARGET="${TARGET}" MCPU="${MCPU}" \
ruby -rjson -rdigest -rshellwords -e '
  root = ENV.fetch("ROOT_DIR")
  database_dir = ENV.fetch("DATABASE_DIR")
  out = ENV.fetch("OUT_DIR")
  variants = Dir[File.join(out, "*.o")].sort.map do |path|
    name = File.basename(path, ".o")
    {
      "name" => name,
      "object" => File.basename(path),
      "bytes" => File.size(path),
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "link_command" => File.read(File.join(out, "#{name}.link-command.txt")).strip,
    }
  end
  payload = {
    "generated_at_utc" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "source_commit" => `git -C #{Shellwords.escape(root)} rev-parse HEAD`.strip,
    "source" => "benchmarks/database/src/server.cr",
    "shard_lock_sha256" => Digest::SHA256.file(File.join(database_dir, "shard.lock")).hexdigest,
    "target" => ENV.fetch("TARGET"),
    "mcpu" => ENV.fetch("MCPU"),
    "stock_compiler" => File.read(File.join(out, "stock-crystal-version.txt")),
    "fork_compiler" => File.read(File.join(out, "acrystal-version.txt")),
    "comparison_invariant" => "same Amber and Grant source, schemas, routes, release settings, target, and linker; only compiler and database adapter flags differ",
    "variants" => variants,
  }
  File.write(File.join(out, "objects-manifest.json"), JSON.pretty_generate(payload))
'

echo
echo "Database workload objects and manifest written to ${OUT_DIR}"
