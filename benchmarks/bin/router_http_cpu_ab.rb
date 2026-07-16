#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"

Binary = Struct.new(:name, :path, keyword_init: true)

options = {
  binaries: [],
  inner_repetitions: 5,
  operations: 200_000,
  output: "benchmarks/results/router_http_cpu_ab.json",
  repetitions: 5,
  routes: 1_000,
  warmup: 20_000,
}

OptionParser.new do |parser|
  parser.banner = "Usage: router_http_cpu_ab.rb --binary=NAME:PATH [options]"
  parser.on("--binary=NAME:PATH", "Binary label and release executable (repeatable)") do |value|
    name, path = value.split(":", 2)
    raise OptionParser::InvalidArgument, value unless name && path
    options[:binaries] << Binary.new(name: name, path: File.expand_path(path))
  end
  parser.on("--routes=COUNT", Integer, "Mixed routes installed by each binary") { |value| options[:routes] = value }
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
  options[:binaries].rotate(repetition % options[:binaries].size).each do |binary|
    raw_path = File.join(raw_dir, "#{binary.name}_r#{repetition + 1}.json")
    command = [
      binary.path,
      "--routes=#{options[:routes]}",
      "--operations=#{options[:operations]}",
      "--warmup=#{options[:warmup]}",
      "--repetitions=#{options[:inner_repetitions]}",
      "--output=#{raw_path}",
    ]
    stdout, stderr, status = Open3.capture3(*command)
    raise "#{binary.name} failed: #{stderr}\n#{stdout}" unless status.success?

    result = JSON.parse(File.read(raw_path))
    summary = result.fetch("summary")
    trial = {
      "strategy" => binary.name,
      "repetition" => repetition + 1,
      "median_requests_per_second" => summary.fetch("median_requests_per_second"),
      "median_bytes_per_request" => summary.fetch("median_bytes_per_request"),
      "compiler" => result.fetch("metadata").fetch("compiler").lines.first.strip,
      "measurements" => result.fetch("results"),
      "raw_result" => File.join(File.basename(raw_dir), File.basename(raw_path)),
    }
    trials << trial
    warn format(
      "%s r%d: %.0f req/s, %.1f B/request",
      binary.name,
      repetition + 1,
      trial["median_requests_per_second"],
      trial["median_bytes_per_request"]
    )
  end
end

aggregates = {}
baseline_rps = nil
baseline_bytes = nil

options[:binaries].each_with_index do |binary, index|
  rows = trials.select { |trial| trial["strategy"] == binary.name }
  rps = summarize(rows.map { |row| row["median_requests_per_second"] })
  bytes = summarize(rows.map { |row| row["median_bytes_per_request"] })
  baseline_rps = rps["median"] if index.zero?
  baseline_bytes = bytes["median"] if index.zero?

  aggregates[binary.name] = {
    "requests_per_second" => rps,
    "bytes_per_request" => bytes,
    "median_rps_ratio_vs_baseline" => baseline_rps ? rps["median"] / baseline_rps : 1.0,
    "median_allocation_ratio_vs_baseline" => baseline_bytes ? bytes["median"] / baseline_bytes : 1.0,
  }
end

payload = {
  "metadata" => {
    "generated_at_utc" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "routes" => options[:routes],
    "operations" => options[:operations],
    "warmup_operations" => options[:warmup],
    "inner_repetitions" => options[:inner_repetitions],
    "process_repetitions" => options[:repetitions],
    "scope" => "same-source parsed HTTP CPU A/B with rotated process order; excludes sockets and kernel scheduling",
    "binaries" => options[:binaries].map do |binary|
      {
        "name" => binary.name,
        "path" => binary.path,
        "sha256" => Digest::SHA256.file(binary.path).hexdigest,
      }
    end,
  },
  "aggregates" => aggregates,
  "trials" => trials,
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(payload))
warn "Wrote #{output_path}"
