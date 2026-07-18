#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${ROOT_DIR:-/opt/amber-density}"
SEED_DIR="${ROOT_DIR}/seed"
RESULT_DIR="${ROOT_DIR}/results"
SQL_DIR="${ROOT_DIR}/sql"
SQLITE_PATH="${SEED_DIR}/benchmark.sqlite3"

mkdir -p "${SEED_DIR}" "${RESULT_DIR}"
rm -f "${SQLITE_PATH}" "${SQLITE_PATH}-shm" "${SQLITE_PATH}-wal"

echo "Seeding the one-million-row SQLite FULL demo template"
/usr/bin/time -v -o "${RESULT_DIR}/sqlite_seed.time.txt" \
  sqlite3 "${SQLITE_PATH}" \
    < "${SQL_DIR}/sqlite_schema_seed.sql" \
    > "${RESULT_DIR}/sqlite_seed.stdout.txt"

sqlite3 "${SQLITE_PATH}" "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA integrity_check;" \
  > "${RESULT_DIR}/sqlite_integrity.txt"

SQLITE_BYTES="$(stat -c %s "${SQLITE_PATH}")"
SQLITE_ROWS="$(sqlite3 "${SQLITE_PATH}" 'SELECT count(*) FROM benchmark_resources')"
SQLITE_USERS="$(sqlite3 "${SQLITE_PATH}" 'SELECT count(*) FROM benchmark_users')"
if [[ "${SQLITE_ROWS}" != "1000000" ]] || [[ "${SQLITE_USERS}" != "10000" ]]; then
  echo "Seed count mismatch: users=${SQLITE_USERS}, resources=${SQLITE_ROWS}" >&2
  exit 1
fi

# shellcheck disable=SC2016
SQLITE_BYTES="${SQLITE_BYTES}" SQLITE_ROWS="${SQLITE_ROWS}" SQLITE_USERS="${SQLITE_USERS}" \
ruby -rjson -e '
  payload = {
    "generated_at_utc" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "sqlite_version" => `sqlite3 --version`.strip,
    "sqlite_database_bytes" => ENV.fetch("SQLITE_BYTES").to_i,
    "sqlite_resource_rows" => ENV.fetch("SQLITE_ROWS").to_i,
    "sqlite_user_rows" => ENV.fetch("SQLITE_USERS").to_i,
    "sqlite_synchronous" => "FULL",
    "sqlite_journal_mode" => "WAL",
    "bcrypt_cost" => 10,
  }
  File.write("/opt/amber-density/results/seed-manifest.json", JSON.pretty_generate(payload))
'

sync
echo 3 > /proc/sys/vm/drop_caches
if swapon --show=NAME --noheadings | grep -qx /swapfile; then
  swapoff /swapfile
fi
rm -f /swapfile

if [[ "$(awk '/SwapTotal/ {print $2}' /proc/meminfo)" != "0" ]]; then
  echo "Swap must be disabled before measurement" >&2
  exit 1
fi

echo "Demo seed ready: ${SQLITE_USERS} users, ${SQLITE_ROWS} resources, ${SQLITE_BYTES} bytes"
