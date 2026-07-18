\set ON_ERROR_STOP on

DROP TABLE IF EXISTS benchmark_resource_events;
DROP TABLE IF EXISTS benchmark_sessions;
DROP TABLE IF EXISTS benchmark_resources;
DROP TABLE IF EXISTS benchmark_users;

CREATE TABLE benchmark_users (
  id BIGINT PRIMARY KEY,
  public_id VARCHAR(36) NOT NULL UNIQUE,
  email VARCHAR(160) NOT NULL UNIQUE,
  password_digest VARCHAR(60) NOT NULL,
  display_name VARCHAR(80) NOT NULL,
  role VARCHAR(24) NOT NULL,
  organization VARCHAR(96) NOT NULL,
  created_at_epoch BIGINT NOT NULL
);

CREATE TABLE benchmark_resources (
  id BIGINT PRIMARY KEY,
  public_id VARCHAR(36) NOT NULL UNIQUE,
  ulid VARCHAR(26) NOT NULL UNIQUE,
  user_id BIGINT NOT NULL,
  title VARCHAR(96) NOT NULL,
  body VARCHAR(255) NOT NULL,
  status VARCHAR(24) NOT NULL,
  score DOUBLE PRECISION NOT NULL,
  version INTEGER NOT NULL,
  updated_at_epoch BIGINT NOT NULL
);

CREATE INDEX benchmark_resources_user_id_id_idx
  ON benchmark_resources (user_id, id DESC);

CREATE TABLE benchmark_sessions (
  token_hash VARCHAR(64) PRIMARY KEY,
  user_id BIGINT NOT NULL,
  expires_at_epoch BIGINT NOT NULL,
  created_at_epoch BIGINT NOT NULL
);

CREATE INDEX benchmark_sessions_user_id_idx ON benchmark_sessions (user_id);

CREATE TABLE benchmark_resource_events (
  id BIGSERIAL PRIMARY KEY,
  resource_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL,
  kind VARCHAR(32) NOT NULL,
  value INTEGER NOT NULL,
  created_at_epoch BIGINT NOT NULL
);

INSERT INTO benchmark_users (
  id, public_id, email, password_digest, display_name, role, organization,
  created_at_epoch
)
SELECT
  i,
  '00000000-0000-4000-8000-' || lpad(to_hex(i), 12, '0'),
  'user' || lpad(i::text, 6, '0') || '@example.test',
  '$2a$10$QGv3LaUYA3tiQpjrHNjuMescMMlrGFe97tW610q2ZMZLrNs89B8Yi',
  'Benchmark User ' || i,
  CASE WHEN i % 20 = 0 THEN 'admin' ELSE 'member' END,
  'Organization ' || ((i - 1) % 250 + 1),
  1704067200 + i
FROM generate_series(1, 10000) AS rows(i);

INSERT INTO benchmark_resources (
  id, public_id, ulid, user_id, title, body, status, score, version,
  updated_at_epoch
)
SELECT
  i,
  '10000000-0000-4000-8000-' || lpad(to_hex(i), 12, '0'),
  '01J8Z3M5N7' || lpad(i::text, 16, '0'),
  ((i - 1) % 10000) + 1,
  'Benchmark Resource ' || i,
  left(
    'Resource payload ' || i || ' ' ||
    repeat('amber-crystal-database-workload-', 8),
    240
  ),
  CASE i % 4
    WHEN 0 THEN 'active'
    WHEN 1 THEN 'pending'
    WHEN 2 THEN 'archived'
    ELSE 'review'
  END,
  (i % 10000)::double precision / 100.0,
  (i % 17)::integer,
  1704067200 + i
FROM generate_series(1, 1000000) AS rows(i);

INSERT INTO benchmark_sessions (
  token_hash, user_id, expires_at_epoch, created_at_epoch
) VALUES (
  '7b529f08962dc96604dc0a21320eaa5f971f3a4ee36369569246bd13e9ff8133',
  1,
  4102444800,
  1704067200
);

ANALYZE benchmark_users;
ANALYZE benchmark_resources;
ANALYZE benchmark_sessions;
ANALYZE benchmark_resource_events;

SELECT 'users' AS table_name, count(*) AS rows FROM benchmark_users
UNION ALL
SELECT 'resources', count(*) FROM benchmark_resources
UNION ALL
SELECT 'sessions', count(*) FROM benchmark_sessions;
