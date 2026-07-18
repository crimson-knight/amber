require "spec"

SPEC_DATABASE_PATH = "/tmp/amber-round23-spec-#{Process.pid}.sqlite3"
ENV["DATABASE_URL"] = "sqlite3:#{SPEC_DATABASE_PATH}?max_pool_size=4&max_idle_pool_size=4&checkout_timeout=2.0&retry_attempts=0"
ENV["SQLITE_SYNCHRONOUS"] = "FULL"

require "../src/application"

module Amber::Benchmarks::DatabaseWorkload::SpecSupport
  extend self

  @@pipeline : Amber::Pipe::Pipeline? = nil

  def database : DB::Database
    Database.connection
  end

  def reset_database : Nil
    statements = [
      "DROP TABLE IF EXISTS benchmark_resource_events",
      "DROP TABLE IF EXISTS benchmark_sessions",
      "DROP TABLE IF EXISTS benchmark_resources",
      "DROP TABLE IF EXISTS benchmark_users",
      <<-SQL,
        CREATE TABLE benchmark_users (
          id INTEGER PRIMARY KEY, public_id TEXT NOT NULL UNIQUE,
          email TEXT NOT NULL UNIQUE, password_digest TEXT NOT NULL,
          display_name TEXT NOT NULL, role TEXT NOT NULL,
          organization TEXT NOT NULL, created_at_epoch INTEGER NOT NULL
        )
        SQL
      <<-SQL,
        CREATE TABLE benchmark_resources (
          id INTEGER PRIMARY KEY, public_id TEXT NOT NULL UNIQUE,
          ulid TEXT NOT NULL UNIQUE, user_id INTEGER NOT NULL,
          title TEXT NOT NULL, body TEXT NOT NULL, status TEXT NOT NULL,
          score REAL NOT NULL, version INTEGER NOT NULL,
          updated_at_epoch INTEGER NOT NULL
        )
        SQL
      "CREATE INDEX benchmark_resources_user_id_id_idx ON benchmark_resources (user_id, id DESC)",
      <<-SQL,
        CREATE TABLE benchmark_sessions (
          token_hash TEXT PRIMARY KEY, user_id INTEGER NOT NULL,
          expires_at_epoch INTEGER NOT NULL, created_at_epoch INTEGER NOT NULL
        )
        SQL
      <<-SQL,
        CREATE TABLE benchmark_resource_events (
          id INTEGER PRIMARY KEY, resource_id INTEGER NOT NULL,
          user_id INTEGER NOT NULL, kind TEXT NOT NULL, value INTEGER NOT NULL,
          created_at_epoch INTEGER NOT NULL
        )
        SQL
    ]
    statements.each { |statement| database.exec(statement) }

    password_digest = Crypto::Bcrypt::Password.create("benchmark-password", cost: 4).to_s
    BenchmarkUser.create!(
      id: 1_i64,
      public_id: "00000000-0000-4000-8000-000000000001",
      email: "user000001@example.test",
      password_digest: password_digest,
      display_name: "Benchmark User",
      role: "member",
      organization: "Benchmark Org",
      created_at_epoch: 1_704_067_201_i64
    )
    BenchmarkResource.create!(
      id: 1_i64,
      public_id: "10000000-0000-4000-8000-000000000001",
      ulid: "01J8Z3M5N70000000000000001",
      user_id: 1_i64,
      title: "Benchmark Resource",
      body: "A realistic resource body",
      status: "active",
      score: 12.5,
      version: 1,
      updated_at_epoch: 1_704_067_201_i64
    )
    BenchmarkSession.create!(
      token_hash: Digest::SHA256.hexdigest("benchmark-session-token-0001"),
      user_id: 1_i64,
      expires_at_epoch: 4_102_444_800_i64,
      created_at_epoch: 1_704_067_200_i64
    )
  end

  def pipeline : Amber::Pipe::Pipeline
    @@pipeline ||= begin
      DatabaseWorkload.install_routes(100)
      Amber::Pipe::Pipeline.new.tap(&.prepare_pipelines)
    end
    @@pipeline.not_nil!
  end

  def request(method : String, path : String, body : String? = nil, token : String? = nil) : {Int32, String}
    raw = String.build do |io|
      io << method << ' ' << path << " HTTP/1.1\r\n"
      io << "Host: benchmark.local\r\nAccept: application/json\r\n"
      io << "Authorization: Bearer " << token << "\r\n" if token
      if body
        io << "Content-Type: application/json\r\nContent-Length: " << body.bytesize << "\r\n"
      end
      io << "Connection: close\r\n\r\n"
      io << body if body
    end
    output = IO::Memory.new
    HTTP::Server::RequestProcessor.new(pipeline).process(IO::Memory.new(raw), output)
    response = output.to_s
    status = response.match(/HTTP\/1\.1 ([0-9]{3})/).not_nil![1].to_i
    {status, response.split("\r\n\r\n", 2).last}
  end
end

Spec.before_suite do
  Amber::Benchmarks::DatabaseWorkload::SpecSupport.reset_database
end

Spec.after_suite do
  Amber::Benchmarks::DatabaseWorkload::Database.connection.close
  File.delete?(SPEC_DATABASE_PATH)
  File.delete?("#{SPEC_DATABASE_PATH}-shm")
  File.delete?("#{SPEC_DATABASE_PATH}-wal")
end

describe Amber::Benchmarks::DatabaseWorkload do
  support = Amber::Benchmarks::DatabaseWorkload::SpecSupport
  token = "benchmark-session-token-0001"

  it "logs in with bcrypt and persists a usable session" do
    status, body = support.request(
      "POST",
      "/api/v1/sessions",
      %({"email":"user000001@example.test","password":"benchmark-password"})
    )
    status.should eq 200
    parsed = JSON.parse(body)
    parsed["token"].as_s.size.should eq 64
    Amber::Benchmarks::DatabaseWorkload::BenchmarkSession.count.should eq 2
  end

  it "loads the same row through integer, UUID, and ULID routes" do
    paths = [
      "/api/v1/resources/1",
      "/api/v1/resources/by-uuid/10000000-0000-4000-8000-000000000001",
      "/api/v1/resources/by-ulid/01J8Z3M5N70000000000000001",
    ]
    paths.each do |path|
      status, body = support.request("GET", path, token: token)
      status.should eq 200
      JSON.parse(body)["id"].as_i.should eq 1
    end
  end

  it "runs authenticated list, calculation, update, and CRUD-cycle work" do
    support.request("GET", "/api/v1/users/1/resources", token: token)[0].should eq 200
    support.request("POST", "/api/v1/resources/1/calculate", token: token)[0].should eq 200
    update_status, update_body = support.request(
      "PATCH",
      "/api/v1/resources/1",
      %({"status":"review","score":99.5}),
      token
    )
    update_status.should eq 200
    JSON.parse(update_body)["version"].as_i.should eq 2

    cycle_status, cycle_body = support.request("POST", "/api/v1/resources/1/crud-cycle", token: token)
    cycle_status.should eq 200
    JSON.parse(cycle_body)["deleted"].as_bool.should be_true
    Amber::Benchmarks::DatabaseWorkload::BenchmarkResourceEvent.count.should eq 0
  end

  it "rejects missing sessions" do
    support.request("GET", "/api/v1/resources/1")[0].should eq 401
  end
end
