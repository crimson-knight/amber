# frozen_string_literal: true

module DemoDensityRound24
  module_function

  def percentile(values, fraction)
    sorted = values.sort
    return 0.0 if sorted.empty?

    sorted[((sorted.length - 1) * fraction).round]
  end

  def summarize(values)
    return {"count" => 0} if values.empty?

    mean = values.sum / values.length.to_f
    variance = values.sum { |value| (value - mean)**2 } / values.length
    {
      "count" => values.length,
      "min" => values.min,
      "median" => percentile(values, 0.5),
      "mean" => mean,
      "max" => values.max,
      "stddev" => Math.sqrt(variance),
      "coefficient_of_variation" => mean.zero? ? 0.0 : Math.sqrt(variance) / mean,
    }
  end

  def fairness(values)
    return 0.0 if values.empty?

    squared_sum = values.sum**2
    denominator = values.length * values.sum { |value| value**2 }
    denominator.zero? ? 0.0 : squared_sum / denominator
  end

  def evaluate_trial(load_result, telemetry, phase)
    overall = load_result.fetch("overall")
    reasons = []
    reasons << "request errors" unless overall.fetch("errors").zero?
    reasons << "incomplete offered load" if overall.fetch("attainment") < phase.fetch("minimum_attainment")
    reasons << "p99 latency" if overall.fetch("p99_seconds") > phase.fetch("maximum_p99_seconds")
    reasons << "tenant unfairness" if overall.fetch("fairness") < phase.fetch("minimum_fairness")
    reasons << "inactive application unit" unless telemetry.fetch("all_units_active")
    reasons << "OOM kill" if telemetry.fetch("oom_kills").positive?
    reasons << "swap activity" if telemetry.fetch("swap_in_pages").positive? || telemetry.fetch("swap_out_pages").positive?
    reasons << "swap enabled" if telemetry.fetch("swap_total_bytes").positive?
    reasons << "memory reserve" if telemetry.fetch("memory_available_fraction") < phase.fetch("minimum_memory_available_fraction")

    {
      "passed" => reasons.empty?,
      "failure_reasons" => reasons,
    }
  end

  def build_summary(payload)
    phases = payload.fetch("metadata").fetch("phases")
    phase_names = phases.map { |phase| phase.fetch("name") }
    repetitions = payload.fetch("metadata").fetch("repetitions")

    payload.fetch("metadata").fetch("targets").to_h do |target|
      label = target.fetch("label")
      target_trials = payload.fetch("trials").select { |trial| trial.fetch("target") == label }
      density_rows = target_trials.group_by { |trial| trial.fetch("density") }.sort.to_h.transform_values do |rows|
        expected = phase_names.length * repetitions
        passed = rows.length == expected && rows.all? { |row| row.dig("gate", "passed") }
        {
          "passed" => passed,
          "trial_count" => rows.length,
          "expected_trial_count" => expected,
          "failure_reasons" => rows.flat_map { |row| row.dig("gate", "failure_reasons") || [] }.uniq.sort,
          "phases" => phase_names.to_h do |phase_name|
            phase_rows = rows.select { |row| row.fetch("phase") == phase_name }
            [phase_name, {
              "requests_per_second" => summarize(phase_rows.map { |row| row.dig("load", "overall", "success_rps") }),
              "p99_seconds" => summarize(phase_rows.map { |row| row.dig("load", "overall", "p99_seconds") }),
              "attainment" => summarize(phase_rows.map { |row| row.dig("load", "overall", "attainment") }),
              "fairness" => summarize(phase_rows.map { |row| row.dig("load", "overall", "fairness") }),
              "cpu_steal_fraction" => summarize(phase_rows.map { |row| row.dig("telemetry", "cpu_steal_fraction") }),
              "memory_available_bytes" => summarize(phase_rows.map { |row| row.dig("telemetry", "memory_available_bytes") }),
            }]
          end,
        }
      end

      healthy_densities = density_rows.select { |_density, row| row.fetch("passed") }.keys
      highest_healthy = healthy_densities.max || 0
      monthly = target.fetch("price_monthly").to_f
      hourly = target.fetch("price_hourly").to_f
      [label, {
        "cpu_class" => target.fetch("cpu_class"),
        "size" => target.fetch("size"),
        "price_monthly" => monthly,
        "price_hourly" => hourly,
        "highest_healthy_density" => highest_healthy,
        "monthly_cost_per_healthy_app" => highest_healthy.zero? ? nil : monthly / highest_healthy,
        "hourly_cost_per_healthy_app" => highest_healthy.zero? ? nil : hourly / highest_healthy,
        "densities" => density_rows,
      }]
    end
  end
end
