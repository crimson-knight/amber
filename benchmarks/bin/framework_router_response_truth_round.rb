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
    key: "plaintext_action_vs_raw",
    label: "Amber plaintext action vs raw Crystal response",
    base: "raw_plaintext",
    candidate: "action_plaintext",
  },
  {
    key: "json_action_direct_vs_raw",
    label: "Amber direct JSON action vs raw Crystal response",
    base: "raw_json",
    candidate: "action_json_direct",
  },
  {
    key: "json_respond_with_vs_direct",
    label: "respond_with JSON vs direct JSON action",
    base: "action_json_direct",
    candidate: "action_json_respond_with",
  },
  {
    key: "query_params_vs_raw",
    label: "Amber params query lookup vs raw HTTP::Params lookup",
    base: "raw_query_lookup",
    candidate: "params_lookup_query",
  },
  {
    key: "query_action_wrapper_vs_raw_action",
    label: "Controller params wrapper query action vs raw params action",
    base: "action_query_raw_params",
    candidate: "action_query_params",
  },
  {
    key: "route_query_dispatch_vs_action",
    label: "Route+query dispatch vs direct controller query action",
    base: "action_query_params",
    candidate: "dispatch_route_query_params",
  },
  {
    key: "json_params_vs_raw_parse",
    label: "Amber JSON params lookup vs raw JSON.parse",
    base: "raw_json_body_parse",
    candidate: "params_lookup_json",
  },
  {
    key: "json_dispatch_vs_params",
    label: "JSON body dispatch vs params lookup",
    base: "params_lookup_json",
    candidate: "dispatch_json_body",
  },
].freeze

LAB_COMPARISONS = [
  {
    key: "plaintext_action_vs_raw",
    comparison_key: "plaintext_controller_vs_raw",
    label: "Amber plaintext action vs raw Crystal response",
  },
  {
    key: "json_action_direct_vs_raw",
    comparison_key: "json_direct_vs_raw",
    label: "Amber direct JSON action vs raw Crystal response",
  },
  {
    key: "json_respond_with_vs_direct",
    comparison_key: "json_respond_with_vs_direct",
    label: "respond_with JSON vs direct JSON action",
  },
  {
    key: "query_params_vs_raw",
    comparison_key: "query_params_vs_raw",
    label: "Amber params query lookup vs raw HTTP::Params lookup",
  },
  {
    key: "query_action_wrapper_vs_raw_action",
    comparison_key: "query_action_wrapper_vs_raw_action",
    label: "Controller params wrapper query action vs raw params action",
  },
  {
    key: "route_query_dispatch_vs_action",
    comparison_key: "route_query_dispatch_vs_action",
    label: "Route+query dispatch vs direct controller query action",
  },
  {
    key: "json_params_vs_raw_parse",
    comparison_key: "json_params_vs_raw_parse",
    label: "Amber JSON params lookup vs raw JSON.parse",
  },
  {
    key: "json_dispatch_vs_params",
    comparison_key: "json_dispatch_vs_params",
    label: "JSON body dispatch vs params lookup",
  },
].freeze

LAB_SCENARIO_KEYS = [
  "raw_plaintext",
  "amber_action_plaintext",
  "raw_json",
  "amber_action_json_direct",
  "amber_action_json_respond_with",
  "raw_query_lookup",
  "amber_params_lookup_query",
  "amber_action_query_raw_params",
  "amber_action_query_params",
  "amber_dispatch_route_query_params",
  "raw_json_body_parse",
  "amber_params_lookup_json",
  "amber_dispatch_json_body",
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
    output_path = File.join(output_dir, "framework_router_response_truth_lab_run_#{index + 1}.json")
    run_cmd(
      binary_path,
      "--warmup=#{warmup_seconds}",
      "--calc=#{calc_seconds}",
      "--scenarios=#{LAB_SCENARIO_KEYS.join(',')}",
      "--output=#{output_path}",
      chdir: File.dirname(binary_path)
    )

    payload = JSON.parse(File.read(output_path))
    metadata_samples << {
      "repetition" => index + 1,
      "output_path" => output_path,
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
  parser.banner = "Usage: ruby benchmarks/bin/framework_router_response_truth_round.rb [options]"

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
compiler_slug = options["compiler"].gsub(%r{[^A-Za-z0-9]+}, "_")
output_path = options["output"] || File.join(repo_root, "benchmarks", "results", "framework_router_response_truth_#{compiler_slug}_#{timestamp}.json")

FileUtils.mkdir_p(File.dirname(output_path))

Dir.mktmpdir("amber-framework-router-response-truth-") do |tmp_dir|
  profile_binary = File.join(tmp_dir, "framework_performance_profile")
  lab_binary = File.join(tmp_dir, "framework_performance_lab")

  run_cmd("bash", File.join(repo_root, "benchmarks/bin/framework_profile_build.sh"), "--compiler", options["compiler"], "--output", profile_binary, chdir: repo_root)
  run_cmd("bash", File.join(repo_root, "benchmarks/bin/framework_perf_build.sh"), "--compiler", options["compiler"], "--output", lab_binary, chdir: repo_root)

  warm_profile_scenarios(profile_binary, options["profile_warmup_duration"])
  profile_pairs = run_profile_pairs(profile_binary, options["profile_duration"], options["profile_repetitions"])
  lab_results = run_lab_repetitions(lab_binary, tmp_dir, options["lab_warmup"], options["lab_calc"], options["lab_repetitions"])

  payload = {
    "metadata" => {
      "generated_at_utc" => Time.now.utc.iso8601,
      "compiler" => options["compiler"],
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
  }

  File.write(output_path, JSON.pretty_generate(payload))
  puts "Wrote #{output_path}"
end
