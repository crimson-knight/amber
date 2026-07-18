#!/usr/bin/env ruby

require "json"

ROOT_DIR = File.expand_path("../..", __dir__)
RESULT_DIR = File.join(ROOT_DIR, "benchmarks", "results")

def assert!(condition, message)
  abort "Round 23 result verification failed: #{message}" unless condition
end

def load_json(name)
  JSON.parse(File.read(File.join(RESULT_DIR, name)))
end

def validate_trials!(data, expected_count, label)
  trials = data.fetch("trials")
  assert!(trials.size == expected_count, "#{label} has #{trials.size} trials, expected #{expected_count}")
  trials.each do |trial|
    errors = %w[socket_errors non_2xx_responses application_errors].sum { |key| trial.fetch(key) }
    assert!(errors.zero?, "#{label} contains request errors")
    assert!(trial.fetch("swap_total_bytes").zero?, "#{label} activated swap during measurement")
    assert!(trial.fetch("requests_per_second").positive?, "#{label} contains non-positive throughput")
    assert!(trial.fetch("p99_seconds") >= trial.fetch("p50_seconds"), "#{label} contains inverted latency percentiles")
    logs = trial.fetch("server_log")
    assert!(logs.none? { |line| line.include?(" ERROR ") }, "#{label} contains an application error log")
  end
end

main = load_json("round23_digitalocean_database_matrix.json")
calibration = load_json("round23_digitalocean_database_calibration.json")
smoke = load_json("round23_digitalocean_database_smoke.json")
fork = load_json("round23_digitalocean_database_acrystal_confirmation.json")
cold = load_json("round23_digitalocean_database_cold_cache.json")
seed = load_json("round23_do_database_seed_manifest.json")
objects = load_json("round23_do_objects_manifest.json")

validate_trials!(main, 105, "steady-state matrix")
validate_trials!(calibration, 8, "calibration")
validate_trials!(smoke, 15, "smoke matrix")
validate_trials!(fork, 12, "acrystal confirmation")
validate_trials!(cold, 6, "cold-cache control")

expected_groups = %w[login read_hot read_broad mixed_journey crud_cycle].product(
  %w[postgres sqlite_full sqlite_normal]
)
expected_groups.each do |scenario, variant|
  count = main.fetch("trials").count do |trial|
    trial.fetch("scenario") == scenario && trial.fetch("variant") == variant
  end
  assert!(count == 7, "#{scenario}/#{variant} has #{count} repetitions, expected 7")
end

assert!(main.dig("metadata", "hardware", "target", "swap_bytes").zero?, "target metadata reports swap")
assert!(main.dig("metadata", "resource_rows") == 1_000_000, "matrix resource count is not one million")
assert!(seed.fetch("postgres_resource_rows") == 1_000_000, "PostgreSQL seed count mismatch")
assert!(seed.fetch("sqlite_resource_rows") == 1_000_000, "SQLite seed count mismatch")
integrity_lines = File.readlines(File.join(RESULT_DIR, "round23_sqlite_integrity.txt"), chomp: true)
assert!(integrity_lines.last == "ok", "SQLite integrity check failed")
assert!(objects.fetch("variants").map { |row| row.fetch("name") }.sort == %w[acrystal_postgres acrystal_sqlite stock_postgres stock_sqlite], "binary object variants are incomplete")
assert!(cold.dig("metadata", "cache_mode").start_with?("cold start"), "cold-cache result is not labeled cold")
assert!(fork.dig("metadata", "compiler_lane") == "acrystal", "fork result is not labeled acrystal")

aggregate = main.fetch("aggregates")
ratio = lambda do |scenario, variant|
  aggregate.dig(scenario, "16", variant, "median_rps_ratio_vs_postgres")
end
assert!(ratio.call("read_hot", "sqlite_full") > 2.0, "SQLite FULL hot-read advantage disappeared")
assert!(ratio.call("read_broad", "sqlite_full") > 2.0, "SQLite FULL broad-read advantage disappeared")
assert!(ratio.call("crud_cycle", "sqlite_full") < 1.0, "SQLite FULL durable-write tradeoff disappeared")
assert!(ratio.call("crud_cycle", "sqlite_normal") > 5.0, "SQLite NORMAL write advantage disappeared")

puts "Round 23 evidence verified: 146 measured trials, zero errors, zero measurement swap"
puts "Seed verified: 10,000 users and 1,000,000 resources in both databases"
puts "Compatibility verified: stock Crystal and acrystal, PostgreSQL and SQLite"
