#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

compiler="crystal"
output_path=""
release_build=1

while (($#)); do
  case "$1" in
    --compiler)
      compiler="${2:?missing value for --compiler}"
      shift 2
      ;;
    --output)
      output_path="${2:?missing value for --output}"
      shift 2
      ;;
    --no-release)
      release_build=0
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: benchmarks/bin/framework_perf_build.sh --compiler crystal|acrystal|/absolute/path --output /absolute/path [--no-release]

Builds the framework performance lab with the normalized Amber benchmark toolchain.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${output_path}" ]]; then
  echo "--output is required" >&2
  exit 1
fi

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

mkdir -p "$(dirname "${output_path}")"

build_args=("${compiler_path}" "build" "--error-trace")
if ((release_build)); then
  build_args+=("--release")
fi
build_args+=("-o" "${output_path}" "benchmarks/framework_performance_lab.cr")

cd "${repo_root}"
exec "${build_args[@]}"
