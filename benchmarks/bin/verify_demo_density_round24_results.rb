#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

ROOT_DIR = File.expand_path("../..", __dir__)
RESULT_DIR = File.join(ROOT_DIR, "benchmarks", "results")
PRIMARY_PATH = File.join(RESULT_DIR, "round24_digitalocean_demo_density.json")
FINAL_PATH = File.join(RESULT_DIR, "round24_demo_density_final.json")
BINARIES_PATH = File.join(ROOT_DIR, "benchmarks", "results", "round24_do_binaries_manifest.json")
SEED_GLOB = File.join(ROOT_DIR, "benchmarks", "results", "round24_*_seed_manifest.json")
INVENTORY_PATH = File.join(ROOT_DIR, "benchmarks", "digitalocean", "amber-density-r24-inventory.json")

def assert(condition, message)
  raise message unless condition
end

primary = JSON.parse(File.read(PRIMARY_PATH))
final = JSON.parse(File.read(FINAL_PATH))
assert(primary.dig("metadata", "completed_at_utc"), "primary result is incomplete")
assert(primary.fetch("trials").length == 144, "expected 144 primary trials")
assert(final.dig("metadata", "capacity_trial_count") == 216, "expected 216 synthesized capacity trials")
assert(final.dig("metadata", "smoke_trial_count") == 6, "expected six smoke trials")

evidence = final.dig("metadata", "evidence_files").transform_values do |filename|
  JSON.parse(File.read(File.join(RESULT_DIR, filename)))
end
capacity_trials = evidence.values.flat_map { |payload| payload.fetch("trials") }
assert(capacity_trials.length == 216, "evidence trial count changed")

expected_capacity = {
  "micro" => {"apps" => 10, "recommended" => 8, "monthly" => 4.0, "cost" => 0.40},
  "shared2x4" => {"apps" => 80, "recommended" => 64, "monthly" => 24.0, "cost" => 0.30},
  "dedicated2x4" => {"apps" => 40, "recommended" => 32, "monthly" => 42.0, "cost" => 1.05},
}
expected_capacity.each do |label, expected|
  plan = final.fetch("plans").fetch(label)
  assert(plan.fetch("healthy_apps") == expected.fetch("apps"), "#{label} healthy density changed")
  assert(plan.fetch("recommended_apps") == expected.fetch("recommended"), "#{label} recommended density changed")
  assert(plan.fetch("price_monthly") == expected.fetch("monthly"), "#{label} monthly price changed")
  assert((plan.fetch("monthly_cost_per_healthy_app") - expected.fetch("cost")).abs < 1e-9, "#{label} cost/app changed")
end

capacity_trials.each_with_index do |trial, index|
  overall = trial.dig("load", "overall")
  telemetry = trial.fetch("telemetry")
  assert(overall.fetch("errors").zero?, "evidence trial #{index + 1} had request errors")
  assert(overall.fetch("fairness") >= 0.90, "evidence trial #{index + 1} failed fairness")
  assert(overall.fetch("attainment") >= 0.95, "evidence trial #{index + 1} failed offered load")
  assert(telemetry.fetch("all_units_active"), "evidence trial #{index + 1} lost an app unit")
  assert(telemetry.fetch("oom_kills").zero?, "evidence trial #{index + 1} had an OOM")
  assert(telemetry.fetch("swap_total_bytes").zero?, "evidence trial #{index + 1} enabled swap")
  assert(telemetry.fetch("swap_in_pages").zero? && telemetry.fetch("swap_out_pages").zero?, "evidence trial #{index + 1} swapped")
end
assert(capacity_trials.count { |trial| !trial.dig("gate", "passed") } == 3, "expected three latency-gate failures")

failed_events = primary.fetch("capacity_events").select { |event| event.fetch("status") != "passed" }
assert(failed_events.any? { |event| event["target"] == "micro" && event["density"] == 12 && event["status"] == "insufficient_storage" }, "missing micro storage boundary")
assert(failed_events.any? { |event| event["target"] == "shared2x4" && event["density"] == 36 && event.fetch("failure_reasons") == ["p99 latency"] }, "missing shared latency boundary")
assert(failed_events.any? { |event| event["target"] == "dedicated2x4" && event["density"] == 44 && event["status"] == "insufficient_storage" }, "missing dedicated storage boundary")

integrity = primary.dig("metadata", "integrity_checks")
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

inventory = JSON.parse(File.read(INVENTORY_PATH))
assert(inventory.fetch("destroyed_at_utc"), "benchmark inventory does not record teardown")
assert(inventory.dig("resources", "targets").length == 3, "inventory target count changed")

puts "Round 24 verified: 216 capacity trials, 6 smoke trials, 90 integrity checks"
puts "Zero request/OOM/swap/integrity errors; teardown recorded"
puts "Capacity: micro=10 ($0.40/app), shared2x4=80 ($0.30/app), dedicated2x4=40 ($1.05/app)"
