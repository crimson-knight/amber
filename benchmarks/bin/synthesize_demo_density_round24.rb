#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"

ROOT_DIR = File.expand_path("../..", __dir__)
RESULT_DIR = File.join(ROOT_DIR, "benchmarks", "results")
OUTPUT_PATH = File.join(RESULT_DIR, "round24_demo_density_final.json")

EVIDENCE_PATHS = {
  "primary" => File.join(RESULT_DIR, "round24_digitalocean_demo_density.json"),
  "shared_boundary_confirmation" => File.join(RESULT_DIR, "round24_shared_boundary_confirmation.json"),
  "shared_extended_capacity" => File.join(RESULT_DIR, "round24_shared_extended_capacity.json"),
  "shared_frontier_capacity" => File.join(RESULT_DIR, "round24_shared_frontier_capacity.json"),
  "shared_frontier_refinement" => File.join(RESULT_DIR, "round24_shared_frontier_refinement.json"),
  "dedicated_boundary_confirmation" => File.join(RESULT_DIR, "round24_dedicated_boundary_confirmation.json"),
  "micro_boundary_confirmation" => File.join(RESULT_DIR, "round24_micro_boundary_confirmation.json"),
}.freeze

def assert(condition, message)
  raise message unless condition
end

def median(values)
  sorted = values.sort
  return 0.0 if sorted.empty?

  middle = sorted.length / 2
  sorted.length.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
end

def statistics(values)
  return {"count" => 0} if values.empty?

  {
    "count" => values.length,
    "min" => values.min,
    "median" => median(values),
    "mean" => values.sum / values.length.to_f,
    "max" => values.max,
  }
end

def phase_metrics(rows)
  %w[steady burst].to_h do |phase|
    phase_rows = rows.select { |trial| trial.fetch("phase") == phase }
    [phase, {
      "trial_count" => phase_rows.length,
      "gate_failures" => phase_rows.count { |trial| !trial.dig("gate", "passed") },
      "success_rps" => statistics(phase_rows.map { |trial| trial.dig("load", "overall", "success_rps") }),
      "p99_milliseconds" => statistics(phase_rows.map { |trial| trial.dig("load", "overall", "p99_seconds") * 1_000 }),
      "attainment" => statistics(phase_rows.map { |trial| trial.dig("load", "overall", "attainment") }),
      "fairness" => statistics(phase_rows.map { |trial| trial.dig("load", "overall", "fairness") }),
      "cpu_steal_percent" => statistics(phase_rows.map { |trial| trial.dig("telemetry", "cpu_steal_fraction") * 100 }),
      "target_cpu_percent" => statistics(phase_rows.map { |trial| trial.dig("telemetry", "target_cpu_utilization") * 100 }),
      "iowait_percent" => statistics(phase_rows.map { |trial| trial.dig("telemetry", "cpu_iowait_fraction") * 100 }),
      "memory_available_mebibytes" => statistics(phase_rows.map { |trial| trial.dig("telemetry", "memory_available_bytes") / 1_048_576.0 }),
      "application_memory_mebibytes" => statistics(phase_rows.map { |trial| trial.dig("telemetry", "application_memory_current_bytes") / 1_048_576.0 }),
    }]
  end
end

evidence = EVIDENCE_PATHS.transform_values { |path| JSON.parse(File.read(path)) }
trials = evidence.values.flat_map { |payload| payload.fetch("trials") }
primary = evidence.fetch("primary")
target_metadata = primary.dig("metadata", "targets").to_h { |target| [target.fetch("label"), target] }

assert(trials.length == 216, "expected 216 capacity trials, found #{trials.length}")
assert(trials.all? { |trial| trial.dig("load", "overall", "errors").zero? }, "a capacity trial had request errors")
assert(trials.all? { |trial| trial.dig("telemetry", "all_units_active") }, "a capacity trial lost an app unit")
assert(trials.all? { |trial| trial.dig("telemetry", "oom_kills").zero? }, "a capacity trial had an OOM")
assert(trials.all? { |trial| trial.dig("telemetry", "swap_total_bytes").zero? }, "a capacity trial enabled swap")

rows_for = lambda do |label, density, keys = EVIDENCE_PATHS.keys|
  keys.flat_map { |key| evidence.fetch(key).fetch("trials") }.select do |trial|
    trial.fetch("target") == label && trial.fetch("density") == density
  end
end

micro_boundary = rows_for.call("micro", 10, %w[primary micro_boundary_confirmation])
shared_boundary = rows_for.call("shared2x4", 80, %w[shared_frontier_capacity])
shared_first_failure = rows_for.call("shared2x4", 84, %w[shared_frontier_refinement])
dedicated_boundary = rows_for.call("dedicated2x4", 40, %w[primary dedicated_boundary_confirmation])

assert(micro_boundary.length == 10 && micro_boundary.all? { |trial| trial.dig("gate", "passed") }, "micro boundary confirmation failed")
assert(shared_boundary.length == 6 && shared_boundary.all? { |trial| trial.dig("gate", "passed") }, "shared boundary confirmation failed")
assert(shared_first_failure.length == 6 && shared_first_failure.count { |trial| !trial.dig("gate", "passed") } == 1, "shared first-failure evidence changed")
assert(dedicated_boundary.length == 10 && dedicated_boundary.all? { |trial| trial.dig("gate", "passed") }, "dedicated boundary confirmation failed")

plan_definitions = {
  "micro" => {
    "healthy_apps" => 10,
    "recommended_apps" => 8,
    "first_failed_density" => 12,
    "limiter" => "storage reserve",
    "boundary_rows" => micro_boundary,
    "limit_evidence" => "density 12 stopped before traffic when another 483,098,624-byte database would violate the 1 GiB disk reserve",
  },
  "shared2x4" => {
    "healthy_apps" => 80,
    "recommended_apps" => 64,
    "first_failed_density" => 84,
    "limiter" => "burst p99 latency",
    "boundary_rows" => shared_boundary,
    "limit_evidence" => "one of three density-84 bursts reached 1,058 ms p99; the other two reached 584 ms and 204 ms, with zero request errors",
  },
  "dedicated2x4" => {
    "healthy_apps" => 40,
    "recommended_apps" => 32,
    "first_failed_density" => 44,
    "limiter" => "storage reserve",
    "boundary_rows" => dedicated_boundary,
    "limit_evidence" => "density 44 stopped before traffic when another 483,098,624-byte database would violate the 1 GiB disk reserve",
  },
}

plans = plan_definitions.to_h do |label, definition|
  target = target_metadata.fetch(label)
  monthly = target.fetch("price_monthly").to_f
  healthy_apps = definition.fetch("healthy_apps")
  recommended_apps = definition.fetch("recommended_apps")
  [label, {
    "size" => target.fetch("size"),
    "cpu_class" => target.fetch("cpu_class"),
    "vcpus" => target.fetch("vcpus"),
    "memory_mb" => target.fetch("memory_mb"),
    "disk_gb" => target.fetch("disk_gb"),
    "price_monthly" => monthly,
    "price_hourly" => target.fetch("price_hourly"),
    "healthy_apps" => healthy_apps,
    "monthly_cost_per_healthy_app" => monthly / healthy_apps,
    "recommended_apps" => recommended_apps,
    "monthly_cost_per_recommended_app" => monthly / recommended_apps,
    "operating_headroom_fraction" => 1.0 - recommended_apps / healthy_apps.to_f,
    "first_failed_density" => definition.fetch("first_failed_density"),
    "limiter" => definition.fetch("limiter"),
    "limit_evidence" => definition.fetch("limit_evidence"),
    "boundary_metrics" => phase_metrics(definition.fetch("boundary_rows")),
  }]
end

shared_at_40 = rows_for.call("shared2x4", 40, %w[shared_extended_capacity])
dedicated_at_40 = dedicated_boundary
shared_36_original = rows_for.call("shared2x4", 36, %w[primary])
shared_36_confirmation = rows_for.call("shared2x4", 36, %w[shared_boundary_confirmation])

integrity = primary.dig("metadata", "integrity_checks")
payload = {
  "metadata" => {
    "generated_at_utc" => Time.now.utc.iso8601,
    "experiment" => "Amber V2 shared-versus-dedicated demo density Round 24",
    "route_count_per_app" => 1_000,
    "users_per_app" => 10_000,
    "resources_per_app" => 1_000_000,
    "database_bytes_per_app" => 483_098_624,
    "database" => "private SQLite WAL with synchronous=FULL",
    "steady_rps_per_app" => 2.0,
    "burst_rps_per_app" => 10.0,
    "capacity_gate" => "zero errors, at least 95% attainment, fair service, steady p99 <=250 ms, burst p99 <=1,000 ms, no OOM/swap, and at least 5% memory available",
    "capacity_trial_count" => trials.length,
    "smoke_trial_count" => JSON.parse(File.read(File.join(RESULT_DIR, "round24_digitalocean_demo_density_smoke.json"))).fetch("trials").length,
    "integrity_databases_checked" => integrity.values.sum { |row| row.fetch("checked") },
    "integrity_failures" => integrity.values.sum { |row| row.fetch("failures") },
    "request_errors" => trials.sum { |trial| trial.dig("load", "overall", "errors") },
    "oom_kills" => trials.sum { |trial| trial.dig("telemetry", "oom_kills") },
    "gate_failure_trials" => trials.count { |trial| !trial.dig("gate", "passed") },
    "evidence_files" => EVIDENCE_PATHS.transform_values { |path| File.basename(path) },
  },
  "plans" => plans,
  "comparisons" => {
    "cost_winner" => "shared2x4",
    "shared_cost_savings_vs_micro" => 1.0 - plans.dig("shared2x4", "monthly_cost_per_healthy_app") / plans.dig("micro", "monthly_cost_per_healthy_app"),
    "dedicated_cost_premium_vs_shared" => plans.dig("dedicated2x4", "monthly_cost_per_healthy_app") / plans.dig("shared2x4", "monthly_cost_per_healthy_app") - 1.0,
    "equal_resource_density_40" => {
      "shared2x4" => phase_metrics(shared_at_40),
      "dedicated2x4" => phase_metrics(dedicated_at_40),
    },
    "shared_density_36_variance" => {
      "original" => phase_metrics(shared_36_original),
      "confirmation" => phase_metrics(shared_36_confirmation),
      "interpretation" => "one original steady trial exceeded 250 ms p99; all six confirmation trials passed, so exploration continued",
    },
    "shared_density_84_failure" => phase_metrics(shared_first_failure),
  },
}

File.write(OUTPUT_PATH, JSON.pretty_generate(payload))
puts "Wrote #{OUTPUT_PATH} from #{trials.length} capacity trials"
