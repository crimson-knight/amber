# Amber same-host database benchmark

This Round 23 workload compares complete Amber V2 applications backed by
PostgreSQL and SQLite on the same one-vCPU DigitalOcean target. It is designed
to answer a deployment question, not crown a database in the abstract:

> On the smallest useful application host, does an in-process SQLite database
> leave enough CPU and memory for Amber to outperform a local PostgreSQL service,
> and where does that answer change as reads become broad or writes contend?

## Invariants

- The Amber source, optimized router, Grant models, schema, indexes, response
  payloads, request order, target machine, load generator, and compiler settings
  remain fixed.
- The route table contains 1,000 entries so every request includes realistic
  framework routing rather than a one-route shortcut.
- The database contains 10,000 users and 1,000,000 resource records.
- Resources expose an integer primary key plus unique UUID and ULID indexes.
- Authenticated requests hash the bearer token and load its database session.
- Login loads a user by indexed email, verifies bcrypt at cost 10, creates a
  cryptographically random token, hashes it, and inserts the session.
- The application and database share the target's single vCPU and memory.
- PostgreSQL uses durable defaults. SQLite is measured with `synchronous=FULL`
  for the closest durability comparison and `synchronous=NORMAL` as an explicit
  operational tradeoff.

## Scenarios

| Scenario | What it exercises |
| --- | --- |
| `login` | indexed user lookup, bcrypt verification, token generation, session insert |
| `read_hot` | authenticated integer, UUID, ULID, and owner-list reads with 70% locality |
| `read_broad` | authenticated lookups spread across the full million-row table |
| `mixed_journey` | periodic login followed by reads, list queries, calculation, update, and CRUD-cycle requests |
| `crud_cycle` | create, read, update, and delete a temporary event through Grant |

Each hosted trial records RPS, p50, p99, errors, Amber CPU and memory, PostgreSQL
CPU and memory when applicable, disk throughput and utilization, page faults,
database and WAL sizes, and CPU-normalized throughput. Warm steady-state trials
are paired and rotated. Cold-cache trials are reported separately.

## Local setup

Install pinned benchmark dependencies:

```shell
cd benchmarks/database
shards install
```

Create and seed SQLite:

```shell
sqlite3 /tmp/amber-round23.sqlite3 < sql/sqlite_schema_seed.sql
```

Run the SQLite server:

```shell
DATABASE_URL='sqlite3:/tmp/amber-round23.sqlite3?initial_pool_size=4&max_pool_size=8&max_idle_pool_size=8' \
  crystal run src/server.cr --release -Ddb_sqlite -- --server
```

PostgreSQL uses the same source with `-Ddb_postgres` and a `DATABASE_URL` such
as `postgres://amber_bench@127.0.0.1:5432/amber_bench?...`.

The hosted lifecycle is managed by the Round 23 scripts under
`benchmarks/digitalocean/`. Provisioning and destruction remain dry-run by
default and refuse to operate outside the `agentc` doctl context.

The completed DigitalOcean experiment, decision guidance, and evidence index
are in [`DIGITALOCEAN_DATABASE_ROUND23.md`](../DIGITALOCEAN_DATABASE_ROUND23.md).
