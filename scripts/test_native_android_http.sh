#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# -ge 1 && $# -le 2 ]] || { echo "Usage: $0 <adb-serial> [evidence-directory]" >&2; exit 2; }
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
: "${ASSET_PIPELINE_ROOT:?Set ASSET_PIPELINE_ROOT}"
source "$ASSET_PIPELINE_ROOT/scripts/android_env.sh"
android_resolve_sdk_root
adb="$ANDROID_RESOLVED_SDK_ROOT/platform-tools/adb"
serial="$1"
evidence="${2:-$(mktemp -d /tmp/amber-http-proof.XXXXXX)}"
mkdir -p "$evidence"
evidence="$(cd "$evidence" && pwd)"
fixture="$(mktemp -d "$evidence/tls-fixture.XXXXXX")"
openssl_bin="${OPENSSL_BIN:-openssl}"
python_bin="${PYTHON_BIN:-python3}"
"$openssl_bin" version > "$evidence/openssl-version.txt"
server_pid=""
mapped=()
cleanup() {
  for port in ${mapped[@]+"${mapped[@]}"}; do "$adb" -s "$serial" reverse --remove "tcp:$port" >/dev/null 2>&1 || true; done
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
"$adb" -s "$serial" reverse --list > "$evidence/reverse-before.txt"
for port in 18443 18444 18445 18446; do
  if grep -Eq "[[:space:]]tcp:$port[[:space:]]" "$evidence/reverse-before.txt"; then
    echo "Device port $port already has a reverse mapping; refusing to overwrite it" >&2; exit 1
  fi
done
"$openssl_bin" req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=AssetPipeline-Ephemeral-Test-CA \
  -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign' \
  -keyout "$fixture/ca.key" -out "$fixture/ca.pem" > "$evidence/certificate-build.txt" 2>&1
for role in trusted wronghost; do
  "$openssl_bin" req -new -newkey rsa:2048 -nodes -subj "/CN=$role" \
    -keyout "$fixture/$role.key" -out "$fixture/$role.csr" >> "$evidence/certificate-build.txt" 2>&1
  extension=localhost
  [[ "$role" != wronghost ]] || extension=wronghost
  "$openssl_bin" x509 -req -days 2 -in "$fixture/$role.csr" -CA "$fixture/ca.pem" -CAkey "$fixture/ca.key" \
    -CAcreateserial -extfile "$repo_root/examples/native_http/$extension.ext" -out "$fixture/$role.pem" >> "$evidence/certificate-build.txt" 2>&1
done
"$openssl_bin" req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=Untrusted-Test-Leaf \
  -addext 'subjectAltName=DNS:localhost' -keyout "$fixture/untrusted.key" -out "$fixture/untrusted.pem" >> "$evidence/certificate-build.txt" 2>&1
cp -R "$repo_root/examples/native_http/debug" "$fixture/debug"
mkdir -p "$fixture/debug/res/raw"
cp "$fixture/ca.pem" "$fixture/debug/res/raw/ap_test_ca.pem"
shasum -a 256 "$fixture/ca.pem" "$fixture/trusted.pem" "$fixture/wronghost.pem" "$fixture/untrusted.pem" > "$evidence/certificate-sha256.txt"
"$python_bin" -u "$repo_root/examples/native_http/server.py" "$fixture" > "$evidence/server.txt" 2>&1 &
server_pid=$!
for attempt in {1..50}; do
  kill -0 "$server_pid" 2>/dev/null || { echo "TLS fixture exited" >&2; exit 1; }
  if grep -q '^READY$' "$evidence/server.txt"; then break; fi
  sleep 0.1
done
grep -q '^READY$' "$evidence/server.txt"
while read -r _ role host_port; do
  [[ "$host_port" =~ ^[0-9]+$ ]] || exit 1
  case "$role" in trusted) device_port=18443 ;; wronghost) device_port=18444 ;; untrusted) device_port=18445 ;; cleartext) device_port=18446 ;; *) exit 1 ;; esac
  "$adb" -s "$serial" reverse "tcp:$device_port" "tcp:$host_port"
  mapped+=("$device_port")
done < <(grep '^PORT ' "$evidence/server.txt")
[[ ${#mapped[@]} == 4 ]]
"$adb" -s "$serial" reverse --list > "$evidence/reverse-during.txt"
AMBER_ANDROID_FIXTURE=http ANDROID_SMOKE_NETWORK_TEST_RESOURCES="$fixture/debug" \
  bash "$repo_root/scripts/test_native_android_app.sh" "$serial" "$evidence"
# Successful HTTP may contact only the trusted server. Neither automatic
# redirects, malformed input nor a disallowed cleartext/TLS endpoint may leak.
if grep -Eq '^REQUEST (wronghost|untrusted|cleartext) |/must-not-follow' "$evidence/server.txt"; then
  echo "HTTP/TLS policy violation in server receipt ledger" >&2; exit 1
fi
for path in ok echo error redirect head large chunk-large slow cancel; do
  grep -Eq "^REQUEST trusted (GET|POST|PATCH|HEAD) /$path$" "$evidence/server.txt"
done
[[ "$(grep -c '^REQUEST trusted GET /cancel$' "$evidence/server.txt")" == 4 ]]
grep -q '^INSTRUMENTATION_STATUS: http_checks=Checks: ' "$evidence/instrumentation.txt"
"$adb" -s "$serial" pull /sdcard/Android/data/dev.assetpipeline.androidhost/files/http-contract.png "$evidence/http-contract.png" > "$evidence/screenshot-pull.txt"
bundle="$ASSET_PIPELINE_ROOT/samples/cross_platform/android_host/app/build/outputs/bundle/release/app-release.aab"
if unzip -Z1 "$bundle" | grep -E 'ap_test_ca|ap_test_network'; then
  echo "Debug TLS test trust material entered the release bundle" >&2; exit 1
fi
echo "PASS: actual Android platform trust, hostname rejection, binary HTTP, response limits, cancellation, and release CA exclusion" | tee "$evidence/http-result.txt"
