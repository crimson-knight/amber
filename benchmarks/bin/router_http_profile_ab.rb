#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"

Binary = Struct.new(:name, :path, keyword_init: true)

options = {
  binaries: [],
  inner_repetitions: 3,
  operations: 100_000,
  output: "benchmarks/results/router_http_profile_ab.json",
  profiles: %w[
    mixed
    static
    rest_integer
    rest_uuid
    rest_ulid
    rest_slug
    dynamic_uuid
    nested_uuid
    constrained_integer
    constrained_uuid
    constrained_ulid
    glob
  ],
  repetitions: 5,
  routes: 1_000,
  warmup: 10_000,
}

OptionParser.new do |parser|
  parser.banner = "Usage: router_http_profile_ab.rb --binary=NAME:PATH [options]"
  parser.on("--binary=NAME:PATH", "Binary label and release executable (repeatable)") do |value|
    name, path = value.split(":", 2)
    raise OptionParser::InvalidArgument, value unless name && path
    options[:binaries] << Binary.new(name: name, path: File.expand_path(path))
  end
  parser.on("--profiles=LIST", "Comma-separated traffic profiles") { |value| options[:profiles] = value.split(",") }
  parser.on("--routes=COUNT", Integer, "Routes installed by each binary") { |value| options[:routes] = value }
  parser.on("--operations=COUNT", Integer, "Parsed requests per inner measurement") { |value| options[:operations] = value }
  parser.on("--warmup=COUNT", Integer, "Warmup requests per process") { |value| options[:warmup] = value }
  parser.on("--inner-repetitions=COUNT", Integer, "Measurements within each process") { |value| options[:inner_repetitions] = value }
  parser.on("--repetitions=COUNT", Integer, "Rotated process repetitions") { |value| options[:repetitions] = value }
  parser.on("--output=PATH", "Combined result JSON") { |value| options[:output] = File.expand_path(value) }
end.parse!

abort "At least two --binary entries are required" if options[:binaries].size < 2
options[:binaries].each do |binary|
  abort "Benchmark binary is not executable: #{binary.path}" unless File.executable?(binary.path)
end

def percentile(values, fraction)
  sorted = values.sort
  return 0.0 if sorted.empty?

  sorted[((sorted.size - 1) * fraction).round]
end

def summarize(values)
  mean = values.sum / values.size
  variance = values.sum { |value| (value - mean)**2 } / values.size
  {
    "count" => values.size,
    "min" => values.min,
    "median" => percentile(values, 0.5),
    "mean" => mean,
    "max" => values.max,
    "stddev" => Math.sqrt(variance),
    "coefficient_of_variation" => mean.zero? ? 0.0 : Math.sqrt(variance) / mean,
  }
end

output_path = File.expand_path(options[:output])
raw_dir = output_path.sub(/\.json\z/, "_raw")
FileUtils.mkdir_p(raw_dir)
trials = []

options[:repetitions].times do |repetition|
  options[:profiles].rotate(repetition % options[:profiles].size).each_with_index do |profile, profile_index|
    binary_order = options[:binaries].rotate((repetition + profile_index) % options[:binaries].size)
    binary_order.each do |binary|
      raw_path = File.join(raw_dir, "#{binary.name}_#{profile}_r#{repetition + 1}.json")
      command = [
        binary.path,
        "--routes=#{options[:routes]}",
        "--profile=#{profile}",
        "--operations=#{options[:operations]}",
        "--warmup=#{options[:warmup]}",
        "--repetitions=#{options[:inner_repetitions]}",
        "--output=#{raw_path}",
      ]
      stdout, stderr, status = Open3.capture3(*command)
      raise "#{binary.name} #{profile} failed: #{stderr}\n#{stdout}" unless status.success?

      result = JSON.parse(File.read(raw_path))
      summary = result.fetch("summary")
      trial = {
        "strategy" => binary.name,
        "profile" => profile,
        "repetition" => repetition + 1,
        "median_requests_per_second" => summary.fetch("median_requests_per_second"),
        "median_bytes_per_request" => summary.fetch("median_bytes_per_request"),
        "compiler" => result.fetch("metadata").fetch("compiler").lines.first.strip,
        "measurements" => result.fetch("results"),
        "raw_result" => File.join(File.basename(raw_dir), File.basename(raw_path)),
      }
      trials << trial
      warn format(
        "%-16s %-20s r%d: %.0f req/s, %.1f B/request",
        binary.name,
        profile,
        repetition + 1,
        trial["median_requests_per_second"],
        trial["median_bytes_per_request"]
      )
    end
  end
end

aggregates = {}
paired_comparisons = {}
baseline = options[:binaries].first

options[:profiles].each do |profile|
  aggregates[profile] = {}
  profile_trials = trials.select { |trial| trial["profile"] == profile }
  baseline_trials = profile_trials.select { |trial| trial["strategy"] == baseline.name }
  baseline_rps = summarize(baseline_trials.map { |trial| trial["median_requests_per_second"] })
  baseline_bytes = summarize(baseline_trials.map { |trial| trial["median_bytes_per_request"] })

  options[:binaries].each do |binary|
    rows = profile_trials.select { |trial| trial["strategy"] == binary.name }
    rps = summarize(rows.map { |row| row["median_requests_per_second"] })
    bytes = summarize(rows.map { |row| row["median_bytes_per_request"] })
    aggregates[profile][binary.name] = {
      "requests_per_second" => rps,
      "bytes_per_request" => bytes,
      "median_rps_ratio_vs_baseline" => rps["median"] / baseline_rps["median"],
      "median_allocation_ratio_vs_baseline" => bytes["median"] / baseline_bytes["median"],
    }
  end

  paired_comparisons[profile] = {}
  options[:binaries].drop(1).each do |binary|
    ratios = baseline_trials.map do |baseline_trial|
      comparison = profile_trials.find do |trial|
        trial["strategy"] == binary.name && trial["repetition"] == baseline_trial["repetition"]
      end
      comparison.fetch("median_requests_per_second") / baseline_trial.fetch("median_requests_per_second")
    end
    paired_comparisons[profile][binary.name] = {
      "baseline" => baseline.name,
      "rps_ratio" => summarize(ratios),
      "rps_wins" => ratios.count { |ratio| ratio > 1.0 },
      "pair_count" => ratios.size,
    }
  end
end

payload = {
  "metadata" => {
    "generated_at_utc" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "routes" => options[:routes],
    "profiles" => options[:profiles],
    "operations" => options[:operations],
    "warmup_operations" => options[:warmup],
    "inner_repetitions" => options[:inner_repetitions],
    "process_repetitions" => options[:repetitions],
    "scope" => "same-source parsed HTTP CPU A/B with rotated profile and process order; excludes sockets and kernel scheduling",
    "binaries" => options[:binaries].map do |binary|
      {
        "name" => binary.name,
        "path" => binary.path,
        "sha256" => Digest::SHA256.file(binary.path).hexdigest,
      }
    end,
  },
  "aggregates" => aggregates,
  "paired_comparisons_vs_first_binary" => paired_comparisons,
  "trials" => trials,
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(payload))
warn "Wrote #{output_path}"
