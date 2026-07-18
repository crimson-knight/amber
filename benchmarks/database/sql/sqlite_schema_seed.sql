.bail on
.timer on

PRAGMA journal_mode = WAL;
PRAGMA synchronous = FULL;
PRAGMA temp_store = MEMORY;
PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS benchmark_resource_events;
DROP TABLE IF EXISTS benchmark_sessions;
DROP TABLE IF EXISTS benchmark_resources;
DROP TABLE IF EXISTS benchmark_users;

CREATE TABLE benchmark_users (
  id INTEGER PRIMARY KEY,
  public_id TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL UNIQUE,
  password_digest TEXT NOT NULL,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL,
  organization TEXT NOT NULL,
  created_at_epoch INTEGER NOT NULL
);

CREATE TABLE benchmark_resources (
  id INTEGER PRIMARY KEY,
  public_id TEXT NOT NULL UNIQUE,
  ulid TEXT NOT NULL UNIQUE,
  user_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  status TEXT NOT NULL,
  score REAL NOT NULL,
  version INTEGER NOT NULL,
  updated_at_epoch INTEGER NOT NULL
);

CREATE TABLE benchmark_sessions (
  token_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL,
  expires_at_epoch INTEGER NOT NULL,
  created_at_epoch INTEGER NOT NULL
);

CREATE TABLE benchmark_resource_events (
  id INTEGER PRIMARY KEY,
  resource_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  value INTEGER NOT NULL,
  created_at_epoch INTEGER NOT NULL
);

BEGIN IMMEDIATE;

WITH RECURSIVE sequence(i) AS (
  SELECT 1
  UNION ALL
  SELECT i + 1 FROM sequence WHERE i < 10000
)
INSERT INTO benchmark_users (
  id, public_id, email, password_digest, display_name, role, organization,
  created_at_epoch
)
SELECT
  i,
  '00000000-0000-4000-8000-' || printf('%012x', i),
  'user' || printf('%06d', i) || '@example.test',
  '$2a$10$QGv3LaUYA3tiQpjrHNjuMescMMlrGFe97tW610q2ZMZLrNs89B8Yi',
  'Benchmark User ' || i,
  CASE WHEN i % 20 = 0 THEN 'admin' ELSE 'member' END,
  'Organization ' || (((i - 1) % 250) + 1),
  1704067200 + i
FROM sequence;

WITH RECURSIVE sequence(i) AS (
  SELECT 1
  UNION ALL
  SELECT i + 1 FROM sequence WHERE i < 1000000
)
INSERT INTO benchmark_resources (
  id, public_id, ulid, user_id, title, body, status, score, version,
  updated_at_epoch
)
SELECT
  i,
  '10000000-0000-4000-8000-' || printf('%012x', i),
  '01J8Z3M5N7' || printf('%016d', i),
  ((i - 1) % 10000) + 1,
  'Benchmark Resource ' || i,
  substr(
    'Resource payload ' || i || ' ' ||
    'amber-crystal-database-workload-amber-crystal-database-workload-' ||
    'amber-crystal-database-workload-amber-crystal-database-workload-' ||
    'amber-crystal-database-workload-amber-crystal-database-workload-' ||
    'amber-crystal-database-workload-amber-crystal-database-workload-',
    1,
    240
  ),
  CASE i % 4
    WHEN 0 THEN 'active'
    WHEN 1 THEN 'pending'
    WHEN 2 THEN 'archived'
    ELSE 'review'
  END,
  (i % 10000) / 100.0,
  i % 17,
  1704067200 + i
FROM sequence;

INSERT INTO benchmark_sessions (
  token_hash, user_id, expires_at_epoch, created_at_epoch
) VALUES (
  '7b529f08962dc96604dc0a21320eaa5f971f3a4ee36369569246bd13e9ff8133',
  1,
  4102444800,
  1704067200
);

COMMIT;

CREATE INDEX benchmark_resources_user_id_id_idx
  ON benchmark_resources (user_id, id DESC);
CREATE INDEX benchmark_sessions_user_id_idx ON benchmark_sessions (user_id);

ANALYZE;
PRAGMA optimize;

SELECT 'users' AS table_name, count(*) AS rows FROM benchmark_users
UNION ALL
SELECT 'resources', count(*) FROM benchmark_resources
UNION ALL
SELECT 'sessions', count(*) FROM benchmark_sessions;
