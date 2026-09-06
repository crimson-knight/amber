#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
evidence_dir="${1:-$(mktemp -d /tmp/amber-native-boundary.XXXXXX)}"
mkdir -p "$evidence_dir"
cd "$repo_root"

crystal spec spec/native
crystal run spec/native/fixtures/isolation.cr -Dwithout_openssl -Dwithout_xml
crystal build spec/native/fixtures/isolation.cr --cross-compile \
  --target aarch64-linux-android31 -Dwithout_openssl -Dwithout_xml \
  -o "$evidence_dir/native-isolation" > "$evidence_dir/cross-build.txt" 2>&1
file "$evidence_dir/native-isolation.o" | tee "$evidence_dir/object.txt"
grep -q 'ELF 64-bit.*ARM aarch64' "$evidence_dir/object.txt"

for entry in amber amber/server/server amber/controller/base amber/jobs amber/mailer amber/schema amber/schema/parser amber/websockets/server; do
  log_file="$evidence_dir/reject-${entry//\//-}.txt"
  if crystal build "src/$entry.cr" --cross-compile --target aarch64-linux-android31 \
      -Dwithout_openssl -Dwithout_xml --no-codegen > "$log_file" 2>&1; then
    echo "ERROR: Android unexpectedly accepted server entrypoint $entry" >&2
    exit 1
  fi
  if ! grep -q 'Amber server-only code cannot be compiled for Android' "$log_file"; then
    echo "ERROR: $entry failed for a different reason; inspect $log_file" >&2
    exit 1
  fi
done

crystal spec spec/amber/schema spec/amber/native_web_integration_spec.cr
echo "Native facade, ARM64 object, eight server import guards, and web schema regressions passed. Evidence: $evidence_dir"
