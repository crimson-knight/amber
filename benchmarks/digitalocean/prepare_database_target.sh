#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${ROOT_DIR:-/opt/amber-database}"
DATA_DIR="${ROOT_DIR}/data"
RESULT_DIR="${ROOT_DIR}/results"
SQL_DIR="${ROOT_DIR}/sql"
SQLITE_PATH="${DATA_DIR}/benchmark.sqlite3"
PG_DATABASE="amber_bench"
PG_USER="amber_bench"
PG_PASSWORD="amber-benchmark-local"

mkdir -p "${DATA_DIR}" "${RESULT_DIR}"

PG_VERSION="$(pg_lsclusters --no-header | awk 'NR == 1 {print $1}')"
PG_CLUSTER="$(pg_lsclusters --no-header | awk 'NR == 1 {print $2}')"
PG_UNIT="postgresql@${PG_VERSION}-${PG_CLUSTER}.service"
PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/${PG_CLUSTER}/conf.d"
mkdir -p "${PG_CONF_DIR}"

cat > "${PG_CONF_DIR}/99-amber-benchmark.conf" <<'EOF'
listen_addresses = '127.0.0.1'
max_connections = 32
shared_buffers = '64MB'
effective_cache_size = '256MB'
work_mem = '2MB'
maintenance_work_mem = '32MB'
wal_compression = on
fsync = on
full_page_writes = on
synchronous_commit = on
log_min_messages = warning
log_min_duration_statement = -1
EOF

systemctl restart "${PG_UNIT}"

runuser -u postgres -- psql --dbname=postgres --set=ON_ERROR_STOP=1 \
  --command="SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${PG_DATABASE}' AND pid <> pg_backend_pid()"
runuser -u postgres -- psql --dbname=postgres --set=ON_ERROR_STOP=1 \
  --command="DROP DATABASE IF EXISTS ${PG_DATABASE}"
runuser -u postgres -- psql --dbname=postgres --set=ON_ERROR_STOP=1 \
  --command="DROP ROLE IF EXISTS ${PG_USER}"
runuser -u postgres -- psql --dbname=postgres --set=ON_ERROR_STOP=1 \
  --command="CREATE ROLE ${PG_USER} LOGIN PASSWORD '${PG_PASSWORD}'"
runuser -u postgres -- psql --dbname=postgres --set=ON_ERROR_STOP=1 \
  --command="CREATE DATABASE ${PG_DATABASE} OWNER ${PG_USER}"

echo "Seeding PostgreSQL"
/usr/bin/time -v -o "${RESULT_DIR}/postgres_seed.time.txt" \
  env PGPASSWORD="${PG_PASSWORD}" psql \
    --host=127.0.0.1 \
    --username="${PG_USER}" \
    --dbname="${PG_DATABASE}" \
    --file="${SQL_DIR}/postgres_schema_seed.sql" \
    > "${RESULT_DIR}/postgres_seed.stdout.txt"

echo "Seeding SQLite"
rm -f "${SQLITE_PATH}" "${SQLITE_PATH}-shm" "${SQLITE_PATH}-wal"
/usr/bin/time -v -o "${RESULT_DIR}/sqlite_seed.time.txt" \
  sqlite3 "${SQLITE_PATH}" \
    < "${SQL_DIR}/sqlite_schema_seed.sql" \
    > "${RESULT_DIR}/sqlite_seed.stdout.txt"

sqlite3 "${SQLITE_PATH}" "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA integrity_check;" \
  > "${RESULT_DIR}/sqlite_integrity.txt"

POSTGRES_BYTES="$(runuser -u postgres -- psql --dbname="${PG_DATABASE}" --tuples-only --no-align --command="SELECT pg_database_size('${PG_DATABASE}')")"
SQLITE_BYTES="$(stat -c %s "${SQLITE_PATH}")"
POSTGRES_ROWS="$(runuser -u postgres -- psql --dbname="${PG_DATABASE}" --tuples-only --no-align --command='SELECT count(*) FROM benchmark_resources')"
SQLITE_ROWS="$(sqlite3 "${SQLITE_PATH}" 'SELECT count(*) FROM benchmark_resources')"

POSTGRES_BYTES="${POSTGRES_BYTES}" SQLITE_BYTES="${SQLITE_BYTES}" \
POSTGRES_ROWS="${POSTGRES_ROWS}" SQLITE_ROWS="${SQLITE_ROWS}" \
PG_VERSION="${PG_VERSION}" PG_UNIT="${PG_UNIT}" ruby -rjson -e '
  payload = {
    "generated_at_utc" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "postgres_version" => ENV.fetch("PG_VERSION"),
    "postgres_unit" => ENV.fetch("PG_UNIT"),
    "postgres_database_bytes" => ENV.fetch("POSTGRES_BYTES").to_i,
    "sqlite_database_bytes" => ENV.fetch("SQLITE_BYTES").to_i,
    "postgres_resource_rows" => ENV.fetch("POSTGRES_ROWS").to_i,
    "sqlite_resource_rows" => ENV.fetch("SQLITE_ROWS").to_i,
    "user_rows" => 10_000,
    "expected_resource_rows" => 1_000_000,
    "bcrypt_cost" => 10,
  }
  abort("PostgreSQL seed count mismatch") unless payload["postgres_resource_rows"] == 1_000_000
  abort("SQLite seed count mismatch") unless payload["sqlite_resource_rows"] == 1_000_000
  File.write("/opt/amber-database/results/database-seed-manifest.json", JSON.pretty_generate(payload))
'

sync
if swapon --show=NAME --noheadings | grep -qx /swapfile; then
  swapoff /swapfile
fi

if [[ "$(awk '/SwapTotal/ {print $2}' /proc/meminfo)" != "0" ]]; then
  echo "Swap must be disabled before measurement" >&2
  exit 1
fi

echo "Database target ready: ${POSTGRES_ROWS} PostgreSQL rows, ${SQLITE_ROWS} SQLite rows, swap disabled"
