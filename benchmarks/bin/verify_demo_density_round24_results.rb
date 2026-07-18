#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

ROOT_DIR = File.expand_path("../..", __dir__)
RESULT_PATH = File.join(ROOT_DIR, "benchmarks", "results", "round24_digitalocean_demo_density.json")
BINARIES_PATH = File.join(ROOT_DIR, "benchmarks", "results", "round24_do_binaries_manifest.json")
SEED_GLOB = File.join(ROOT_DIR, "benchmarks", "results", "round24_*_seed_manifest.json")

def assert(condition, message)
  raise message unless condition
end

result = JSON.parse(File.read(RESULT_PATH))
assert(result.dig("metadata", "completed_at_utc"), "result is incomplete")
assert(result.fetch("trials").length == 144, "expected 144 measured trials")

expected_capacity = {
  "micro" => {"apps" => 10, "monthly" => 4.0, "cost" => 0.40},
  "shared2x4" => {"apps" => 32, "monthly" => 24.0, "cost" => 0.75},
  "dedicated2x4" => {"apps" => 40, "monthly" => 42.0, "cost" => 1.05},
}
expected_capacity.each do |label, expected|
  summary = result.fetch("summary").fetch(label)
  assert(summary.fetch("highest_healthy_density") == expected.fetch("apps"), "#{label} healthy density changed")
  assert(summary.fetch("price_monthly") == expected.fetch("monthly"), "#{label} monthly price changed")
  assert((summary.fetch("monthly_cost_per_healthy_app") - expected.fetch("cost")).abs < 1e-9, "#{label} cost/app changed")
end

result.fetch("trials").each do |trial|
  overall = trial.dig("load", "overall")
  telemetry = trial.fetch("telemetry")
  assert(overall.fetch("errors").zero?, "trial #{trial.fetch('sequence')} had request errors")
  assert(overall.fetch("fairness") >= 0.90, "trial #{trial.fetch('sequence')} failed fairness")
  assert(overall.fetch("attainment") >= 0.95, "trial #{trial.fetch('sequence')} failed offered load")
  assert(telemetry.fetch("all_units_active"), "trial #{trial.fetch('sequence')} lost an app unit")
  assert(telemetry.fetch("oom_kills").zero?, "trial #{trial.fetch('sequence')} had an OOM")
  assert(telemetry.fetch("swap_total_bytes").zero?, "trial #{trial.fetch('sequence')} enabled swap")
  assert(telemetry.fetch("swap_in_pages").zero? && telemetry.fetch("swap_out_pages").zero?, "trial #{trial.fetch('sequence')} swapped")
end

failed_events = result.fetch("capacity_events").select { |event| event.fetch("status") != "passed" }
assert(failed_events.any? { |event| event["target"] == "micro" && event["density"] == 12 && event["status"] == "insufficient_storage" }, "missing micro storage boundary")
assert(failed_events.any? { |event| event["target"] == "shared2x4" && event["density"] == 36 && event.fetch("failure_reasons") == ["p99 latency"] }, "missing shared latency boundary")
assert(failed_events.any? { |event| event["target"] == "dedicated2x4" && event["density"] == 44 && event["status"] == "insufficient_storage" }, "missing dedicated storage boundary")

integrity = result.dig("metadata", "integrity_checks")
assert(integrity.values.sum { |row| row.fetch("checked") } == 90, "expected 90 cloned database checks")
assert(integrity.values.all? { |row| row.fetch("failures").zero? }, "database integrity failure")

binaries = JSON.parse(File.read(BINARIES_PATH)).fetch("binaries")
stock_sqlite = binaries.find { |binary| binary.fetch("name") == "stock_sqlite" }
assert(stock_sqlite, "stock_sqlite binary missing from manifest")
assert(stock_sqlite.fetch("sha256").match?(/\A[0-9a-f]{64}\z/), "invalid stock_sqlite hash")

seed_manifests = Dir[SEED_GLOB].map { |path| JSON.parse(File.read(path)) }
assert(seed_manifests.length == 3, "expected three target seed manifests")
assert(seed_manifests.map { |seed| seed.fetch("sqlite_database_bytes") }.uniq == [483_098_624], "seed sizes differ")
assert(seed_manifests.all? { |seed| seed.fetch("sqlite_resource_rows") == 1_000_000 }, "resource seed counts differ")
assert(seed_manifests.all? { |seed| seed.fetch("sqlite_user_rows") == 10_000 }, "user seed counts differ")

puts "Round 24 verified: 144 trials, 90 integrity checks, zero request/OOM/swap errors"
puts "Capacity: micro=10 ($0.40/app), shared2x4=32 ($0.75/app), dedicated2x4=40 ($1.05/app)"
