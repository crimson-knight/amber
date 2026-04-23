#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "time"
require "tmpdir"

PROFILE_PAIRS = [
  {
    key: "query_simple",
    label: "Simple compiled query vs runtime validated",
    base: "action_query_validated_params",
    candidate: "action_query_compiled_validated_params",
  },
  {
    key: "query_hybrid",
    label: "Hybrid compiled query vs mixed runtime validated",
    base: "action_query_mixed_validated_params",
    candidate: "action_query_hybrid_validated_params",
  },
  {
    key: "query_predicate_only",
    label: "Predicate-only compiled query vs runtime validated",
    base: "action_query_predicate_only_validated_params",
    candidate: "action_query_predicate_only_compiled_validated_params",
  },
  {
    key: "json_body_simple",
    label: "Simple compiled JSON body vs runtime validated",
    base: "action_json_body_validated_params",
    candidate: "action_json_body_compiled_validated_params",
  },
  {
    key: "json_body_hybrid",
    label: "Hybrid compiled JSON body vs mixed runtime validated",
    base: "action_json_body_mixed_validated_params",
    candidate: "action_json_body_hybrid_validated_params",
  },
].freeze

LAB_COMPARISONS = [
  {
    key: "query_simple",
    comparison_key: "query_action_compiled_vs_validated",
    label: "Simple compiled query vs runtime validated",
  },
  {
    key: "query_hybrid",
    comparison_key: "query_action_hybrid_vs_mixed",
    label: "Hybrid compiled query vs mixed runtime validated",
  },
  {
    key: "json_body_simple",
    comparison_key: "json_body_action_compiled_vs_validated",
    label: "Simple compiled JSON body vs runtime validated",
  },
  {
    key: "json_body_hybrid",
    comparison_key: "json_body_action_hybrid_vs_mixed",
    label: "Hybrid compiled JSON body vs mixed runtime validated",
  },
].freeze

VALIDATION_SCENARIO_KEYS = [
  "amber_action_query_validated_params",
  "amber_action_query_compiled_validated_params",
  "amber_action_query_mixed_validated_params",
  "amber_action_query_hybrid_validated_params",
  "amber_action_json_body_validated_params",
  "amber_action_json_body_compiled_validated_params",
  "amber_action_json_body_mixed_validated_params",
  "amber_action_json_body_hybrid_validated_params",
].freeze

def median(values)
  sorted = values.sort
  midpoint = sorted.length / 2
  if sorted.length.odd?
    sorted[midpoint]
  else
    (sorted[midpoint - 1] + sorted[midpoint]) / 2.0
  end
end

def mean(values)
  values.sum(0.0) / values.length
end

def standard_deviation(values)
  return 0.0 if values.length < 2

  avg = mean(values)
  variance = values.sum(0.0) { |value| (value - avg)**2 } / (values.length - 1)
  Math.sqrt(variance)
end

def ratio_stats(ratios)
  avg = mean(ratios)
  stdev = standard_deviation(ratios)

  {
    "sample_count" => ratios.length,
    "ratios" => ratios,
    "median_ratio" => median(ratios),
    "mean_ratio" => avg,
    "min_ratio" => ratios.min,
    "max_ratio" => ratios.max,
    "stddev_ratio" => stdev,
    "cv_ratio" => avg.zero? ? 0.0 : stdev / avg,
    "positive_samples" => ratios.count { |value| value > 1.0 },
  }
end

def run_cmd(*cmd, chdir:)
  output, status = Open3.capture2e(*cmd, chdir: chdir)
  raise "Command failed (#{status.exitstatus}): #{cmd.join(' ')}\n#{output}" unless status.success?

  output
end

def run_profile_scenario(binary_path, scenario, duration)
  output = run_cmd(binary_path, "--scenario=#{scenario}", "--duration=#{duration}", chdir: File.dirname(binary_path))
  iterations = output[/Iterations: (\d+)/, 1]
  raise "Unable to parse iterations for #{scenario}\n#{output}" unless iterations

  {
    "scenario" => scenario,
    "iterations" => iterations.to_i,
    "duration_seconds" => duration,
    "raw_output" => output,
  }
end

def warm_profile_scenarios(binary_path, duration)
  PROFILE_PAIRS.flat_map { |pair| [pair[:base], pair[:candidate]] }.uniq.each do |scenario|
    run_profile_scenario(binary_path, scenario, duration)
  end
end

def run_profile_pairs(binary_path, duration, repetitions)
  pair_results = {}

  PROFILE_PAIRS.each do |pair|
    runs = []

    repetitions.times do |index|
      order = index.even? ? [pair[:base], pair[:candidate]] : [pair[:candidate], pair[:base]]
      measured = order.map { |scenario| run_profile_scenario(binary_path, scenario, duration) }
      measured_by_scenario = measured.to_h { |entry| [entry["scenario"], entry] }
      base_iterations = measured_by_scenario.fetch(pair[:base])["iterations"].to_f
      candidate_iterations = measured_by_scenario.fetch(pair[:candidate])["iterations"].to_f

      runs << {
        "repetition" => index + 1,
        "order" => order,
        "base_iterations" => base_iterations.to_i,
        "candidate_iterations" => candidate_iterations.to_i,
        "ratio" => candidate_iterations / base_iterations,
      }
    end

    ratios = runs.map { |entry| entry["ratio"] }
    pair_results[pair[:key]] = {
      "label" => pair[:label],
      "base_scenario" => pair[:base],
      "candidate_scenario" => pair[:candidate],
      "runs" => runs,
    }.merge(ratio_stats(ratios))
  end

  pair_results
end

def run_lab_repetitions(binary_path, output_dir, warmup_seconds, calc_seconds, repetitions)
  comparison_samples = Hash.new { |hash, key| hash[key] = [] }
  metadata_samples = []

  repetitions.times do |index|
    output_path = File.join(output_dir, "framework_validation_truth_lab_run_#{index + 1}.json")
    run_cmd(
      binary_path,
      "--warmup=#{warmup_seconds}",
      "--calc=#{calc_seconds}",
      "--scenarios=#{VALIDATION_SCENARIO_KEYS.join(',')}",
      "--output=#{output_path}",
      chdir: File.dirname(binary_path)
    )

    payload = JSON.parse(File.read(output_path))
    metadata_samples << {
      "repetition" => index + 1,
      "output_path" => output_path,
      "validation_definitions" => payload.fetch("metadata").fetch("validation_definitions"),
    }

    comparison_index = payload.fetch("summary").fetch("comparisons").to_h do |comparison|
      [comparison.fetch("key"), comparison]
    end

    LAB_COMPARISONS.each do |comparison|
      comparison_samples[comparison[:key]] << comparison_index.fetch(comparison[:comparison_key]).fetch("ips_ratio")
    end
  end

  {
    "samples" => metadata_samples,
    "comparisons" => LAB_COMPARISONS.to_h do |comparison|
      [comparison[:key], {
        "label" => comparison[:label],
        "comparison_key" => comparison[:comparison_key],
      }.merge(ratio_stats(comparison_samples.fetch(comparison[:key])))]
    end,
  }
end

def compiler_label(compiler)
  if compiler.include?("/")
    compiler
  else
    compiler
  end
end

def compiler_verdict(profile_pairs, lab_pairs)
  simple_profile_floor = [profile_pairs.fetch("query_simple")["median_ratio"], profile_pairs.fetch("json_body_simple")["median_ratio"]].min
  hybrid_profile_floor = [profile_pairs.fetch("query_hybrid")["median_ratio"], profile_pairs.fetch("json_body_hybrid")["median_ratio"]].min
  lab_floor = [
    lab_pairs.fetch("query_simple")["median_ratio"],
    lab_pairs.fetch("query_hybrid")["median_ratio"],
    lab_pairs.fetch("json_body_simple")["median_ratio"],
    lab_pairs.fetch("json_body_hybrid")["median_ratio"],
  ].min

  if lab_floor >= 1.03 && simple_profile_floor >= 1.0 && hybrid_profile_floor >= 1.0
    {
      "status" => "keep",
      "reason" => "Both the repeated full-lab and repeated focused profile medians stayed positive.",
    }
  elsif lab_floor >= 1.03 && profile_pairs.fetch("query_hybrid")["median_ratio"] >= 1.0
    {
      "status" => "provisional",
      "reason" => "The repeated full-lab stayed positive and the targeted hybrid query case held up, but some focused-profile medians were still negative.",
    }
  else
    {
      "status" => "reject",
      "reason" => "The repeated focused profile did not support a clean across-the-board win strongly enough to promote this path.",
    }
  end
end

options = {
  "compiler" => "crystal",
  "profile_duration" => 4.0,
  "profile_warmup_duration" => 0.75,
  "profile_repetitions" => 5,
  "lab_warmup" => 0.5,
  "lab_calc" => 0.75,
  "lab_repetitions" => 3,
  "output" => nil,
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby benchmarks/bin/framework_validation_truth_round.rb [options]"

  parser.on("--compiler=NAME", "Compiler to use: crystal, acrystal, or an absolute path") do |value|
    options["compiler"] = value
  end

  parser.on("--profile-duration=SECONDS", Float, "Measured duration for each focused profile scenario") do |value|
    options["profile_duration"] = value
  end

  parser.on("--profile-warmup-duration=SECONDS", Float, "One-time warmup duration for each focused scenario") do |value|
    options["profile_warmup_duration"] = value
  end

  parser.on("--profile-repetitions=N", Integer, "How many alternating-order repetitions to run for each focused pair") do |value|
    options["profile_repetitions"] = value
  end

  parser.on("--lab-warmup=SECONDS", Float, "Warmup seconds for each repeated framework-lab run") do |value|
    options["lab_warmup"] = value
  end

  parser.on("--lab-calc=SECONDS", Float, "Calculation seconds for each repeated framework-lab run") do |value|
    options["lab_calc"] = value
  end

  parser.on("--lab-repetitions=N", Integer, "How many repeated framework-lab runs to collect") do |value|
    options["lab_repetitions"] = value
  end

  parser.on("--output=PATH", "Where to write the JSON summary") do |value|
    options["output"] = value
  end
end.parse!

repo_root = File.expand_path("../..", __dir__)
timestamp = Time.now.utc.strftime("%Y%m%d_%H%M%S")
output_path = options["output"] || File.join(repo_root, "benchmarks", "results", "framework_validation_truth_#{options['compiler'].gsub(%r{[^A-Za-z0-9]+}, '_')}_#{timestamp}.json")

FileUtils.mkdir_p(File.dirname(output_path))

Dir.mktmpdir("amber-framework-validation-truth-") do |tmp_dir|
  profile_binary = File.join(tmp_dir, "framework_performance_profile")
  lab_binary = File.join(tmp_dir, "framework_performance_lab")

  run_cmd("bash", File.join(repo_root, "benchmarks/bin/framework_profile_build.sh"), "--compiler", options["compiler"], "--output", profile_binary, chdir: repo_root)
  run_cmd("bash", File.join(repo_root, "benchmarks/bin/framework_perf_build.sh"), "--compiler", options["compiler"], "--output", lab_binary, chdir: repo_root)

  warm_profile_scenarios(profile_binary, options["profile_warmup_duration"])
  profile_pairs = run_profile_pairs(profile_binary, options["profile_duration"], options["profile_repetitions"])
  lab_results = run_lab_repetitions(lab_binary, tmp_dir, options["lab_warmup"], options["lab_calc"], options["lab_repetitions"])

  verdict = compiler_verdict(profile_pairs, lab_results.fetch("comparisons"))

  payload = {
    "metadata" => {
      "generated_at_utc" => Time.now.utc.iso8601,
      "compiler" => compiler_label(options["compiler"]),
      "profile_duration_seconds" => options["profile_duration"],
      "profile_warmup_duration_seconds" => options["profile_warmup_duration"],
      "profile_repetitions" => options["profile_repetitions"],
      "lab_warmup_seconds" => options["lab_warmup"],
      "lab_calc_seconds" => options["lab_calc"],
      "lab_repetitions" => options["lab_repetitions"],
      "branch" => run_cmd("git", "rev-parse", "--abbrev-ref", "HEAD", chdir: repo_root).strip,
      "commit" => run_cmd("git", "rev-parse", "HEAD", chdir: repo_root).strip,
    },
    "profile_pairs" => profile_pairs,
    "lab" => lab_results,
    "verdict" => verdict,
  }

  File.write(output_path, JSON.pretty_generate(payload))
  puts "Wrote #{output_path}"
  puts "Verdict: #{verdict.fetch('status')} - #{verdict.fetch('reason')}"
end
