require "db"

{% if flag?(:db_postgres) && flag?(:db_sqlite) %}
  {% raise "select exactly one database adapter" %}
{% elsif flag?(:db_postgres) %}
  require "grant/adapter/pg"
{% elsif flag?(:db_sqlite) %}
  require "grant/adapter/sqlite"
{% else %}
  {% raise "compile with -Ddb_postgres or -Ddb_sqlite" %}
{% end %}

module Amber::Benchmarks::DatabaseWorkload
  module Database
    extend self

    NAME = "benchmark"

    {% if flag?(:db_postgres) %}
      ADAPTER     = "postgresql"
      DEFAULT_URL = "postgres://amber_bench@127.0.0.1:5432/amber_bench?initial_pool_size=4&max_pool_size=8&max_idle_pool_size=8&checkout_timeout=5.0&retry_attempts=0"
    {% else %}
      ADAPTER     = "sqlite"
      DEFAULT_URL = "sqlite3:/tmp/amber-round23.sqlite3?initial_pool_size=4&max_pool_size=8&max_idle_pool_size=8&checkout_timeout=5.0&retry_attempts=0"
    {% end %}

    URL = ENV["DATABASE_URL"]? || DEFAULT_URL

    def register : Nil
      return if Grant::Connections[NAME]

      {% if flag?(:db_postgres) %}
        Grant::ConnectionRegistry.establish_connection(
          database: NAME,
          adapter: Grant::Adapter::Pg,
          url: URL,
          role: :writing,
          pool_size: 8,
          initial_pool_size: 4,
          checkout_timeout: 5.seconds,
          retry_attempts: 0
        )
      {% else %}
        Grant::ConnectionRegistry.establish_connection(
          database: NAME,
          adapter: Grant::Adapter::Sqlite,
          url: URL,
          role: :writing,
          pool_size: 8,
          initial_pool_size: 0,
          checkout_timeout: 5.seconds,
          retry_attempts: 0
        )
        configure_sqlite
      {% end %}
    end

    def connection : DB::Database
      Grant::ConnectionRegistry.get_adapter(NAME, :writing).database
    end

    def sqlite_synchronous : String
      ENV["SQLITE_SYNCHRONOUS"]? || "FULL"
    end

    private def configure_sqlite : Nil
      synchronous = sqlite_synchronous.upcase
      unless synchronous.in?("FULL", "NORMAL")
        raise ArgumentError.new("SQLITE_SYNCHRONOUS must be FULL or NORMAL")
      end

      database = connection
      database.setup_connection do |conn|
        conn.exec "PRAGMA busy_timeout = 5000"
        conn.exec "PRAGMA foreign_keys = ON"
        conn.exec "PRAGMA temp_store = MEMORY"
        conn.exec "PRAGMA synchronous = #{synchronous}"
        conn.exec "PRAGMA wal_autocheckpoint = 1000"
      end
      database.exec "PRAGMA journal_mode = WAL"
    end
  end
end

Amber::Benchmarks::DatabaseWorkload::Database.register
