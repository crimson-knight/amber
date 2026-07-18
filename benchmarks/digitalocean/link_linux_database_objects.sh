#!/usr/bin/env bash

set -euo pipefail

OBJECT_DIR="${1:-/opt/amber-database/objects}"
BIN_DIR="${2:-/opt/amber-database/bin}"

mkdir -p "${BIN_DIR}"

for command in cc ldd lld pkg-config ruby sha256sum; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Missing required command: ${command}" >&2
    exit 1
  }
done

shopt -s nullglob
objects=("${OBJECT_DIR}"/*.o)
if [[ "${#objects[@]}" -eq 0 ]]; then
  echo "No Crystal object files found in ${OBJECT_DIR}" >&2
  exit 1
fi

read -r -a ssl_flags <<< "$(pkg-config --libs libssl libcrypto)"
read -r -a database_flags <<< "$(pkg-config --libs libpq sqlite3)"

for object in "${objects[@]}"; do
  name="$(basename "${object}" .o)"
  binary="${BIN_DIR}/${name}"
  echo "Linking ${name}"
  cc "${object}" -o "${binary}" \
    -rdynamic \
    -fuse-ld=lld \
    -lyaml \
    -lxml2 \
    -lz \
    "${ssl_flags[@]}" \
    "${database_flags[@]}" \
    -lpcre2-8 \
    -lm \
    -lgc \
    -lpthread \
    -ldl
  chmod 0755 "${binary}"
  ldd "${binary}" > "${binary}.ldd.txt"
done

# shellcheck disable=SC2016
BIN_DIR="${BIN_DIR}" ruby -rjson -rdigest -e '
  dir = ENV.fetch("BIN_DIR")
  binaries = Dir[File.join(dir, "*")].select { |path| File.file?(path) && File.executable?(path) }.sort.map do |path|
    {
      "name" => File.basename(path),
      "bytes" => File.size(path),
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "ldd" => File.read("#{path}.ldd.txt"),
    }
  end
  File.write(File.join(dir, "binaries-manifest.json"), JSON.pretty_generate({
    "generated_at_utc" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "host" => `uname -a`.strip,
    "binaries" => binaries,
  }))
'

echo "Linked binaries and manifest written to ${BIN_DIR}"
