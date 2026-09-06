#!/usr/bin/env bash
set -euo pipefail

[[ $# -ge 1 && $# -le 2 ]] || { echo "Usage: $0 <adb-serial> [evidence-directory]" >&2; exit 2; }
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
: "${ASSET_PIPELINE_ROOT:?Set ASSET_PIPELINE_ROOT to the AssetPipeline checkout with the Android host}"
asset_root="$(cd "$ASSET_PIPELINE_ROOT" && pwd)"
[[ -f "$asset_root/scripts/run_android_smoke.sh" ]] || { echo "AssetPipeline Android host runner not found" >&2; exit 1; }
evidence_dir="${2:-$(mktemp -d /tmp/amber-native-android.XXXXXX)}"
mkdir -p "$evidence_dir"
evidence_dir="$(cd "$evidence_dir" && pwd)"

# Only expose the intended shard, never a parent containing other checkouts
# (a sibling crystal/src can otherwise shadow the compiler's standard library).
# This local integration lane intentionally uses checkouts, not released shards.
shard_lookup="$(mktemp -d "$evidence_dir/shards.XXXXXX")"
ln -s "$asset_root" "$shard_lookup/asset_pipeline"
export CRYSTAL_PATH="$shard_lookup:${CRYSTAL_PATH:-$(crystal env CRYSTAL_PATH)}"
case "${AMBER_ANDROID_FIXTURE:-counter}" in
  notifications)
    export ASSET_PIPELINE_ANDROID_ENTRYPOINT="$repo_root/examples/native_notifications/android.cr"
    export ANDROID_SMOKE_EXTRA_TEST_SOURCE="$repo_root/examples/native_notifications/androidTest"
    export ANDROID_SMOKE_TEST_CLASS="dev.assetpipeline.androidhost.AmberNotificationsTest"
    export ANDROID_SMOKE_NOTIFICATION_TEST_RESOURCES="$repo_root/examples/native_notifications/debug"
    export ANDROID_SMOKE_RESET_NOTIFICATION_PERMISSION=1
    export ANDROID_SMOKE_APP_SLUG=notifications-preview
    export ANDROID_SMOKE_EXPECTED_TEXT="Local notifications ready"
    ;;
  notifications-denied)
    [[ -z "${ANDROID_SMOKE_NOTIFICATION_TEST_RESOURCES:-}" && "${ANDROID_SMOKE_RESET_NOTIFICATION_PERMISSION:-0}" == 0 ]] || { echo "Denied notification proof cannot enable/reset the capability" >&2; exit 1; }
    export ASSET_PIPELINE_ANDROID_ENTRYPOINT="$repo_root/examples/native_notifications/android.cr"
    export ANDROID_SMOKE_EXTRA_TEST_SOURCE="$repo_root/examples/native_notifications/androidTest"
    export ANDROID_SMOKE_TEST_CLASS="dev.assetpipeline.androidhost.AmberNotificationsDeniedTest"
    export ANDROID_SMOKE_APP_SLUG=notifications-denied
    export ANDROID_SMOKE_EXPECTED_TEXT="Notifications require explicit app opt-in"
    ;;
  counter)
    export ASSET_PIPELINE_ANDROID_ENTRYPOINT="$repo_root/examples/hybrid_counter/android.cr"
    export ANDROID_SMOKE_EXTRA_TEST_SOURCE="$repo_root/examples/hybrid_counter/androidTest"
    export ANDROID_SMOKE_TEST_CLASS="dev.assetpipeline.androidhost.AmberNativeApplicationTest"
    export ANDROID_SMOKE_APP_SLUG=amber-counter
    export ANDROID_SMOKE_EXPECTED_TEXT="Shared Amber counter"
    ;;
  storage)
    export ASSET_PIPELINE_ANDROID_ENTRYPOINT="$repo_root/examples/native_storage/android.cr"
    export ANDROID_SMOKE_EXTRA_TEST_SOURCE="$repo_root/examples/native_storage/androidTest"
    export ANDROID_SMOKE_TEST_CLASS="dev.assetpipeline.androidhost.AmberStorageTest"
    export ANDROID_SMOKE_APP_SLUG=storage-contract
    export ANDROID_SMOKE_EXPECTED_TEXT="Storage contract passed: 78 checks"
    ;;
  files)
    export ASSET_PIPELINE_ANDROID_ENTRYPOINT="$repo_root/examples/native_files/android.cr"
    export ANDROID_SMOKE_EXTRA_TEST_SOURCE="$repo_root/examples/native_files/androidTest"
    export ANDROID_SMOKE_TEST_CLASS="dev.assetpipeline.androidhost.AmberFilesTest"
    export ANDROID_SMOKE_APP_SLUG=files-reopen
    export ANDROID_SMOKE_EXPECTED_TEXT="Binary file restored after process restart"
    export ANDROID_SMOKE_REQUIRE_NEW_PROCESS=1
    ;;
  secrets)
    export ASSET_PIPELINE_ANDROID_ENTRYPOINT="$repo_root/examples/native_secrets/android.cr"
    export ANDROID_SMOKE_EXTRA_TEST_SOURCE="$repo_root/examples/native_secrets/androidTest"
    export ANDROID_SMOKE_TEST_CLASS="dev.assetpipeline.androidhost.AmberSecretsTest"
    export ANDROID_SMOKE_APP_SLUG=secrets-reopen
    export ANDROID_SMOKE_EXPECTED_TEXT="Protected test value restored after process restart"
    export ANDROID_SMOKE_REQUIRE_NEW_PROCESS=1
    ;;
  http)
    : "${ANDROID_SMOKE_NETWORK_TEST_RESOURCES:?Run scripts/test_native_android_http.sh for the controlled TLS fixture}"
    export ASSET_PIPELINE_ANDROID_ENTRYPOINT="$repo_root/examples/native_http/android.cr"
    export ANDROID_SMOKE_EXTRA_TEST_SOURCE="$repo_root/examples/native_http/androidTest"
    export ANDROID_SMOKE_TEST_CLASS="dev.assetpipeline.androidhost.AmberHTTPTest"
    export ANDROID_SMOKE_APP_SLUG=http-preview
    export ANDROID_SMOKE_EXPECTED_TEXT="HTTP adapter ready"
    ;;
  http-denied)
    [[ -z "${ANDROID_SMOKE_NETWORK_TEST_RESOURCES:-}" ]] || { echo "Denied-permission proof must not include TLS permission overrides" >&2; exit 1; }
    export ASSET_PIPELINE_ANDROID_ENTRYPOINT="$repo_root/examples/native_http/android.cr"
    export ANDROID_SMOKE_EXTRA_TEST_SOURCE="$repo_root/examples/native_http/androidTest"
    export ANDROID_SMOKE_TEST_CLASS="dev.assetpipeline.androidhost.AmberHTTPDeniedTest"
    export ANDROID_SMOKE_APP_SLUG=http-denied
    export ANDROID_SMOKE_EXPECTED_TEXT="HTTP permission denied correctly"
    ;;
  *) echo "Unknown AMBER_ANDROID_FIXTURE" >&2; exit 2 ;;
esac

while IFS= read -r -d '' source_path; do
  [[ -f "$repo_root/$source_path" ]] || continue
  (cd "$repo_root" && shasum -a 256 "$source_path")
done < <(git -C "$repo_root" ls-files --cached --others --exclude-standard -z -- src examples/hybrid_counter examples/native_storage examples/native_secrets examples/native_files examples/native_http examples/native_notifications scripts/test_native*) > "$evidence_dir/amber-source-sha256.txt"
git -C "$repo_root" rev-parse HEAD > "$evidence_dir/amber-base-commit.txt"
git -C "$repo_root" status --short > "$evidence_dir/amber-source-status.txt"

bash "$asset_root/scripts/run_android_smoke.sh" "$1" "$evidence_dir"
echo "Amber shared use-case Android proof passed: $evidence_dir"
