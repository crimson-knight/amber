#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "time"
require "tmpdir"

RESPONDER_PAIRS = [
  {
    key: "single_json_accept_vs_direct",
    label: "single-format respond_with JSON with Accept vs direct JSON",
    base: "action_json_direct",
    candidate: "action_json_respond_with",
  },
  {
    key: "single_json_macro_vs_runtime",
    label: "single-format macro respond_with JSON with Accept vs runtime responder",
    base: "action_json_respond_with_runtime",
    candidate: "action_json_respond_with",
  },
  {
    key: "single_json_no_accept_vs_direct",
    label: "single-format respond_with JSON without Accept vs direct JSON",
    base: "action_json_direct_no_accept",
    candidate: "action_json_respond_with_no_accept",
  },
  {
    key: "single_json_no_accept_macro_vs_runtime",
    label: "single-format macro respond_with JSON without Accept vs runtime responder",
    base: "action_json_respond_with_no_accept_runtime",
    candidate: "action_json_respond_with_no_accept",
  },
  {
    key: "multi_html_default_vs_direct",
    label: "multi-format respond_with HTML default vs direct HTML",
    base: "action_html_direct",
    candidate: "action_multi_respond_with_html_default",
  },
  {
    key: "multi_html_default_macro_vs_runtime",
    label: "multi-format macro respond_with HTML default vs runtime responder",
    base: "action_multi_respond_with_html_default_runtime",
    candidate: "action_multi_respond_with_html_default",
  },
  {
    key: "multi_html_accept_vs_default",
    label: "multi-format respond_with HTML Accept vs default negotiation",
    base: "action_multi_respond_with_html_default",
    candidate: "action_multi_respond_with_html_accept",
  },
  {
    key: "multi_html_accept_macro_vs_runtime",
    label: "multi-format macro respond_with HTML Accept vs runtime responder",
    base: "action_multi_respond_with_html_accept_runtime",
    candidate: "action_multi_respond_with_html_accept",
  },
  {
    key: "multi_json_accept_vs_direct",
    label: "multi-format respond_with JSON Accept vs direct JSON",
    base: "action_json_direct",
    candidate: "action_multi_respond_with_json_accept",
  },
  {
    key: "multi_json_macro_vs_runtime",
    label: "multi-format macro respond_with JSON Accept vs runtime responder",
    base: "action_multi_respond_with_json_accept_runtime",
    candidate: "action_multi_respond_with_json_accept",
  },
  {
    key: "multi_json_wildcard_vs_accept",
    label: "multi-format respond_with JSON wildcard Accept vs JSON Accept",
    base: "action_multi_respond_with_json_accept",
    candidate: "action_multi_respond_with_json_wildcard",
  },
  {
    key: "multi_path_json_vs_accept",
    label: "multi-format respond_with .json extension vs JSON Accept",
    base: "action_multi_respond_with_json_accept",
    candidate: "action_multi_respond_with_path_json",
  },
  {
    key: "schema_named_tuple_vs_direct",
    label: "schema respond_with NamedTuple JSON vs direct JSON",
    base: "action_json_direct_no_accept",
    candidate: "action_schema_named_tuple_respond_with",
  },
  {
    key: "heavy_json_macro_vs_runtime",
    label: "lazy macro JSON response skips expensive HTML branch",
    base: "action_heavy_respond_with_json_accept_runtime",
    candidate: "action_heavy_respond_with_json_accept",
  },
  {
    key: "heavy_html_macro_vs_runtime",
    label: "lazy macro HTML response when expensive HTML branch is selected",
    base: "action_heavy_respond_with_html_accept_runtime",
    candidate: "action_heavy_respond_with_html_accept",
  },
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
  RESPONDER_PAIRS.flat_map { |pair| [pair[:base], pair[:candidate]] }.uniq.each do |scenario|
    run_profile_scenario(binary_path, scenario, duration)
  end
end

def run_responder_pairs(binary_path, duration, repetitions)
  RESPONDER_PAIRS.to_h do |pair|
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
    [pair[:key], {
      "label" => pair[:label],
      "base_scenario" => pair[:base],
      "candidate_scenario" => pair[:candidate],
      "runs" => runs,
    }.merge(ratio_stats(ratios))]
  end
end

options = {
  "compiler" => "crystal",
  "profile_duration" => 4.0,
  "profile_warmup_duration" => 0.75,
  "profile_repetitions" => 5,
  "output" => nil,
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby benchmarks/bin/framework_respond_with_truth_round.rb [options]"

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

  parser.on("--output=PATH", "Where to write the JSON summary") do |value|
    options["output"] = value
  end
end.parse!

repo_root = File.expand_path("../..", __dir__)
timestamp = Time.now.utc.strftime("%Y%m%d_%H%M%S")
compiler_slug = options["compiler"].gsub(%r{[^A-Za-z0-9]+}, "_")
output_path = options["output"] || File.join(repo_root, "benchmarks", "results", "framework_respond_with_truth_#{compiler_slug}_#{timestamp}.json")

FileUtils.mkdir_p(File.dirname(output_path))

Dir.mktmpdir("amber-framework-respond-with-truth-") do |tmp_dir|
  profile_binary = File.join(tmp_dir, "framework_performance_profile")

  run_cmd("bash", File.join(repo_root, "benchmarks/bin/framework_profile_build.sh"), "--compiler", options["compiler"], "--output", profile_binary, chdir: repo_root)

  warm_profile_scenarios(profile_binary, options["profile_warmup_duration"])
  responder_pairs = run_responder_pairs(profile_binary, options["profile_duration"], options["profile_repetitions"])

  payload = {
    "metadata" => {
      "generated_at_utc" => Time.now.utc.iso8601,
      "compiler" => options["compiler"],
      "profile_duration_seconds" => options["profile_duration"],
      "profile_warmup_duration_seconds" => options["profile_warmup_duration"],
      "profile_repetitions" => options["profile_repetitions"],
      "branch" => run_cmd("git", "rev-parse", "--abbrev-ref", "HEAD", chdir: repo_root).strip,
      "commit" => run_cmd("git", "rev-parse", "HEAD", chdir: repo_root).strip,
    },
    "profile_pairs" => responder_pairs,
  }

  File.write(output_path, JSON.pretty_generate(payload))
  puts "Wrote #{output_path}"
end
