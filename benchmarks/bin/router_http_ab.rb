#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "timeout"

Server = Struct.new(:name, :binary, keyword_init: true)

options = {
  connections: [1, 50],
  duration: "10s",
  host: "127.0.0.1",
  output: "benchmarks/results/router_http_ab.json",
  port: 41_019,
  repetitions: 3,
  routes: 1_000,
  servers: [],
  url_file: nil,
  warmup: "2s",
}

OptionParser.new do |parser|
  parser.banner = "Usage: router_http_ab.rb --server=NAME:PATH --url-file=PATH [options]"
  parser.on("--server=NAME:PATH", "Server label and release binary (repeatable)") do |value|
    name, binary = value.split(":", 2)
    raise OptionParser::InvalidArgument, value unless name && binary
    options[:servers] << Server.new(name: name, binary: File.expand_path(binary))
  end
  parser.on("--url-file=PATH", "oha file containing the mixed request URLs") { |value| options[:url_file] = File.expand_path(value) }
  parser.on("--connections=LIST", "Comma-separated connection counts") { |value| options[:connections] = value.split(",").map(&:to_i) }
  parser.on("--duration=TIME", "Measured duration per trial") { |value| options[:duration] = value }
  parser.on("--warmup=TIME", "Warmup duration per server") { |value| options[:warmup] = value }
  parser.on("--repetitions=COUNT", Integer, "Measured repetitions") { |value| options[:repetitions] = value }
  parser.on("--routes=COUNT", Integer, "Routes installed by each server") { |value| options[:routes] = value }
  parser.on("--host=HOST", "Benchmark server host") { |value| options[:host] = value }
  parser.on("--port=PORT", Integer, "Benchmark server port") { |value| options[:port] = value }
  parser.on("--output=PATH", "Combined result JSON") { |value| options[:output] = File.expand_path(value) }
end.parse!

abort "At least two --server entries are required" if options[:servers].size < 2
abort "--url-file is required" unless options[:url_file]
abort "URL file does not exist: #{options[:url_file]}" unless File.file?(options[:url_file])

options[:servers].each do |server|
  abort "Server binary is not executable: #{server.binary}" unless File.executable?(server.binary)
end

output_path = File.expand_path(options[:output])
raw_dir = output_path.sub(/\.json\z/, "_raw")
FileUtils.mkdir_p(raw_dir)

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

def run_oha(url_file:, connections:, duration:, output:)
  command = [
    "env", "NO_COLOR=true", "oha", "--no-tui", "--output-format", "json",
    "--output", output, "--urls-from-file", "-z", duration,
    "-c", connections.to_s, url_file,
  ]
  raise "oha failed: #{command.join(" ")}" unless system(*command, out: File::NULL, err: $stderr)
  JSON.parse(File.read(output))
end

def with_server(server, host:, port:, routes:)
  command = [server.binary, "--host=#{host}", "--port=#{port}", "--routes=#{routes}"]
  Open3.popen2e(*command, pgroup: true) do |stdin, output, wait_thread|
    stdin.close
    startup = []
    Timeout.timeout(20) do
      loop do
        line = output.gets
        raise "#{server.name} exited before READY" unless line
        startup << line.strip
        break if line.start_with?("READY ")
      end
    end

    yield startup
  ensure
    if wait_thread&.alive?
      Process.kill("INT", -wait_thread.pid)
      Timeout.timeout(5) { wait_thread.join }
    end
  end
end

trials = []

options[:repetitions].times do |repetition|
  options[:servers].rotate(repetition % options[:servers].size).each do |server|
    with_server(server, host: options[:host], port: options[:port], routes: options[:routes]) do |startup|
      options[:connections].each do |connections|
        warmup_path = File.join(raw_dir, "warmup_#{server.name}_r#{repetition + 1}_c#{connections}.json")
        run_oha(
          url_file: options[:url_file],
          connections: connections,
          duration: options[:warmup],
          output: warmup_path
        )

        raw_path = File.join(raw_dir, "#{server.name}_r#{repetition + 1}_c#{connections}.json")
        result = run_oha(
          url_file: options[:url_file],
          connections: connections,
          duration: options[:duration],
          output: raw_path
        )

        summary = result.fetch("summary")
        statuses = result.fetch("statusCodeDistribution")
        raise "#{server.name} returned non-200 responses: #{statuses}" unless statuses.keys == ["200"]

        trial = {
          "strategy" => server.name,
          "repetition" => repetition + 1,
          "connections" => connections,
          "requests_per_second" => summary.fetch("requestsPerSec"),
          "average_seconds" => summary.fetch("average"),
          "p50_seconds" => result.fetch("latencyPercentiles").fetch("p50"),
          "p95_seconds" => result.fetch("latencyPercentiles").fetch("p95"),
          "p99_seconds" => result.fetch("latencyPercentiles").fetch("p99"),
          "successful_responses" => statuses.fetch("200"),
          "success_rate" => summary.fetch("successRate"),
          "raw_result" => raw_path,
          "startup" => startup,
        }
        trials << trial
        warn format(
          "%s r%d c%d: %.0f RPS, p50 %.1f us, p99 %.1f us",
          server.name,
          repetition + 1,
          connections,
          trial["requests_per_second"],
          trial["p50_seconds"] * 1_000_000,
          trial["p99_seconds"] * 1_000_000
        )
      end
    end
  end
end

aggregates = {}
options[:connections].each do |connections|
  connection_key = connections.to_s
  aggregates[connection_key] = {}
  baseline_median = nil

  options[:servers].each_with_index do |server, index|
    rows = trials.select { |trial| trial["strategy"] == server.name && trial["connections"] == connections }
    rps = summarize(rows.map { |row| row["requests_per_second"] })
    p50 = summarize(rows.map { |row| row["p50_seconds"] })
    p99 = summarize(rows.map { |row| row["p99_seconds"] })
    baseline_median = rps["median"] if index.zero?

    aggregates[connection_key][server.name] = {
      "requests_per_second" => rps,
      "p50_seconds" => p50,
      "p99_seconds" => p99,
      "median_rps_ratio_vs_baseline" => baseline_median ? rps["median"] / baseline_median : 1.0,
    }
  end
end

payload = {
  "metadata" => {
    "generated_at_utc" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "host" => options[:host],
    "port" => options[:port],
    "routes" => options[:routes],
    "url_file" => options[:url_file],
    "duration" => options[:duration],
    "warmup" => options[:warmup],
    "repetitions" => options[:repetitions],
    "connections" => options[:connections],
    "servers" => options[:servers].map do |server|
      {
        "name" => server.name,
        "binary" => server.binary,
        "sha256" => Digest::SHA256.file(server.binary).hexdigest,
      }
    end,
  },
  "aggregates" => aggregates,
  "trials" => trials,
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(payload))
warn "Wrote #{output_path}"
