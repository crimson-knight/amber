#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

compiler="crystal"
run_doctor=1
benchmark_args=()

while (($#)); do
  case "$1" in
    --compiler)
      compiler="${2:?missing value for --compiler}"
      shift 2
      ;;
    --skip-doctor)
      run_doctor=0
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: benchmarks/bin/router_strategy_compare.sh [--compiler crystal|acrystal|/absolute/path] [--skip-doctor] [benchmark args...]

Examples:
  benchmarks/bin/router_strategy_compare.sh --compiler crystal --tiers=100,1000 --warmup=1 --calc=1
  benchmarks/bin/router_strategy_compare.sh --compiler acrystal --tiers=100,1000,5000 --warmup=2 --calc=5
EOF
      exit 0
      ;;
    *)
      benchmark_args+=("$1")
      shift
      ;;
  esac
done

resolve_compiler() {
  local value="$1"

  if [[ "$value" == */* ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  command -v "$value"
}

normalize_macos_env() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return 0
  fi

  local xcode_bin="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
  local pkgconf_bin="/opt/homebrew/opt/pkgconf/bin"

  PATH="${pkgconf_bin}:${xcode_bin}:/usr/bin:/bin:/usr/sbin:/sbin"
  export PATH

  if [[ -z "${SDKROOT:-}" ]] && command -v xcrun >/dev/null 2>&1; then
    SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
    export SDKROOT
  fi
}

compiler_path="$(resolve_compiler "$compiler" || true)"
if [[ -z "${compiler_path}" || ! -x "${compiler_path}" ]]; then
  echo "Unable to resolve compiler: ${compiler}" >&2
  exit 1
fi

normalize_macos_env

export AMBER_BENCH_COMPILER="${compiler_path}"

if ((run_doctor)); then
  bash "${script_dir}/crystal_runtime_doctor.sh" --compiler "${compiler_path}"
fi

cd "${repo_root}"
exec "${compiler_path}" run benchmarks/router_strategy_compare.cr -- "${benchmark_args[@]}"
