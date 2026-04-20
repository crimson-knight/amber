#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

compiler="crystal"

while (($#)); do
  case "$1" in
    --compiler)
      compiler="${2:?missing value for --compiler}"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: benchmarks/bin/crystal_runtime_doctor.sh [--compiler crystal|acrystal|/absolute/path]

Builds and runs a tiny Crystal program with the normalized Amber benchmark
toolchain so we can distinguish compiler/linker problems from local runtime
policy problems.
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
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

python3 - "$compiler_path" "$repo_root" <<'PY'
import os
import pathlib
import subprocess
import time
import sys
import tempfile

compiler = sys.argv[1]
repo_root = sys.argv[2]
workdir = pathlib.Path(tempfile.mkdtemp(prefix="amber-router-doctor-", dir="/tmp"))
binary = workdir / "smoke"

env = os.environ.copy()
env.setdefault("CRYSTAL_CACHE_DIR", tempfile.mkdtemp(prefix="amber-router-cache-"))

print(f"Compiler: {compiler}")
print(f"SDKROOT: {env.get('SDKROOT', '(unset)')}")
print(f"PATH: {env.get('PATH', '')}")

build = subprocess.run(
    [compiler, "build", "--error-trace", "--stdin-filename", "smoke.cr", "-o", str(binary)],
    input="puts 1 + 1\n",
    cwd=repo_root,
    env=env,
    capture_output=True,
    text=True,
)

if build.returncode != 0:
    print("\nBuild failed.\n")
    if build.stdout:
        print(build.stdout)
    if build.stderr:
        print(build.stderr, file=sys.stderr)
    sys.exit(build.returncode)

print(f"Build succeeded: {binary}")

attempts = [(5, 0), (10, 2), (10, 2)]
run = None
for index, (timeout, delay) in enumerate(attempts, start=1):
    if delay:
        time.sleep(delay)

    try:
        run = subprocess.run(
            [str(binary)],
            cwd=repo_root,
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if index > 1:
            print(f"\nRuntime smoke test passed on retry {index}.")
        break
    except subprocess.TimeoutExpired:
        if index == len(attempts):
            print(
                "\nRuntime smoke test timed out after repeated launch attempts.\n"
                "The compiler produced a runnable binary, but this machine is "
                "stalling or blocking newly built executables. Fix the local "
                "execution policy before trusting benchmark runs."
            )
            sys.exit(2)

if run.returncode != 0:
    print("\nRuntime smoke test failed.\n")
    if run.stdout:
        print(run.stdout)
    if run.stderr:
        print(run.stderr, file=sys.stderr)
    sys.exit(run.returncode)

output = run.stdout.strip()
if output != "2":
    print(f"\nUnexpected runtime output: {output!r}")
    sys.exit(3)

print("\nRuntime smoke test passed.")
PY
