#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "shellwords"
require "tempfile"
require "time"

Binary = Struct.new(:name, :remote_path, keyword_init: true)

options = {
  binaries: [],
  binary_source_commit: nil,
  connections: [1, 16, 64, 256],
  duration: "10s",
  inventory: nil,
  output: "benchmarks/results/round20_digitalocean_ab.json",
  port: 41_019,
  repetitions: 5,
  routes: 1_000,
  ssh_key: File.expand_path("~/.ssh/agentc_droplets_id_ed25519"),
  warmup: "3s",
}

OptionParser.new do |parser|
  parser.banner = "Usage: router_digitalocean_ab.rb --inventory=PATH --binary=NAME:PATH [options]"
  parser.on("--inventory=PATH", "Provisioned lab inventory JSON") { |value| options[:inventory] = File.expand_path(value) }
  parser.on("--binary=NAME:PATH", "Strategy label and target executable (repeatable)") do |value|
    name, path = value.split(":", 2)
    raise OptionParser::InvalidArgument, value unless name && path
    options[:binaries] << Binary.new(name: name, remote_path: path)
  end
  parser.on("--binary-source-commit=SHA", "Commit used to compile the deployed binaries") { |value| options[:binary_source_commit] = value }
  parser.on("--connections=LIST", "Comma-separated connection counts") { |value| options[:connections] = value.split(",").map(&:to_i) }
  parser.on("--duration=TIME", "Measured duration per trial") { |value| options[:duration] = value }
  parser.on("--warmup=TIME", "Warmup duration per trial") { |value| options[:warmup] = value }
  parser.on("--repetitions=COUNT", Integer, "Rotated process repetitions") { |value| options[:repetitions] = value }
  parser.on("--routes=COUNT", Integer, "Mixed routes installed on the target") { |value| options[:routes] = value }
  parser.on("--port=PORT", Integer, "Private benchmark port") { |value| options[:port] = value }
  parser.on("--ssh-key=PATH", "Private key used for both hosts") { |value| options[:ssh_key] = File.expand_path(value) }
  parser.on("--output=PATH", "Combined result JSON") { |value| options[:output] = File.expand_path(value) }
end.parse!

abort "--inventory is required" unless options[:inventory]
abort "At least two --binary entries are required" if options[:binaries].size < 2
abort "Inventory not found: #{options[:inventory]}" unless File.file?(options[:inventory])
abort "SSH private key not found: #{options[:ssh_key]}" unless File.file?(options[:ssh_key])

inventory = JSON.parse(File.read(options[:inventory]))
target = inventory.fetch("resources").fetch("target")
loadgen = inventory.fetch("resources").fetch("loadgen")
known_hosts = "/tmp/#{inventory.fetch("prefix")}-runner-known-hosts"
FileUtils.touch(known_hosts)

ssh_options = [
  "-i", options[:ssh_key],
  "-o", "BatchMode=yes",
  "-o", "ConnectTimeout=10",
  "-o", "StrictHostKeyChecking=accept-new",
  "-o", "UserKnownHostsFile=#{known_hosts}",
]

def capture!(*command)
  stdout, stderr, status = Open3.capture3(*command)
  return stdout if status.success?

  raise "Command failed (#{status.exitstatus}): #{command.join(" ")}\n#{stderr}\n#{stdout}"
end

def ssh_capture(host, ssh_options, command)
  capture!("ssh", *ssh_options, "root@#{host}", "bash", "-lc", Shellwords.escape(command))
end

def scp_capture(source, destination, ssh_options)
  capture!("scp", *ssh_options, source, destination)
end

def parse_properties(output)
  output.lines.each_with_object({}) do |line, properties|
    key, value = line.strip.split("=", 2)
    properties[key] = value if key && value
  end
end

def parse_time_verbose(output)
  output.lines.each_with_object({}) do |line, properties|
    next unless line.include?(":")
    key, value = line.strip.split(":", 2)
    properties[key] = value.strip
  end
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

def safe_unit_name(strategy, repetition, connections)
  normalized = strategy.gsub(/[^a-zA-Z0-9]+/, "-").downcase
  "amber-router-#{normalized}-r#{repetition}-c#{connections}"
end

def start_server(target, loadgen, ssh_options, binary, unit, options, url_file: false)
  args = [
    binary.remote_path,
    "--host=#{target.fetch("private_ip")}",
    "--port=#{options.fetch(:port)}",
    "--routes=#{options.fetch(:routes)}",
  ]
  args << "--url-file=/opt/amber-router/urls.txt" if url_file

  command = [
    "systemd-run", "--quiet", "--collect", "--unit=#{unit}",
    "--property=CPUAccounting=yes", "--property=MemoryAccounting=yes",
    *args,
  ].map { |value| Shellwords.escape(value) }.join(" ")
  ssh_capture(target.fetch("public_ip"), ssh_options, command)

  ready_url = "http://#{target.fetch("private_ip")}:#{options.fetch(:port)}/api/v1/resource_0/index"
  readiness = "for i in $(seq 1 100); do curl -fsS --max-time 1 #{Shellwords.escape(ready_url)} >/dev/null && exit 0; sleep 0.1; done; exit 1"
  ssh_capture(loadgen.fetch("public_ip"), ssh_options, readiness)
end

def stop_server(target, ssh_options, unit)
  ssh_capture(target.fetch("public_ip"), ssh_options, "systemctl stop #{Shellwords.escape(unit)}.service >/dev/null 2>&1 || true")
end

def unit_stats(target, ssh_options, unit)
  output = ssh_capture(
    target.fetch("public_ip"),
    ssh_options,
    "systemctl show #{Shellwords.escape(unit)}.service --no-pager --property=CPUUsageNSec --property=MemoryCurrent --property=MemoryPeak --property=MainPID --property=TasksCurrent"
  )
  parse_properties(output)
end

def run_oha(loadgen, ssh_options, connections, duration, output_stem, measured: true)
  result_path = "/tmp/#{output_stem}.json"
  time_path = "/tmp/#{output_stem}.time.txt"
  command = [
    "/usr/local/bin/oha", "--no-tui", "--output-format", "json",
    "--output", result_path, "--urls-from-file", "-z", duration,
    "-c", connections.to_s, "/opt/amber-router/urls.txt",
  ].map { |value| Shellwords.escape(value) }.join(" ")

  if measured
    remote = "/usr/bin/time -v -o #{Shellwords.escape(time_path)} #{command} >/dev/null && cat #{Shellwords.escape(result_path)} && printf '\\n---TIME---\\n' && cat #{Shellwords.escape(time_path)}"
    output = ssh_capture(loadgen.fetch("public_ip"), ssh_options, remote)
    json, timing = output.split("\n---TIME---\n", 2)
    [JSON.parse(json), parse_time_verbose(timing || "")]
  else
    ssh_capture(loadgen.fetch("public_ip"), ssh_options, "#{command} >/dev/null")
    nil
  end
end

output_path = File.expand_path(options[:output])
raw_dir = output_path.sub(/\.json\z/, "_raw")
FileUtils.mkdir_p(raw_dir)

options[:binaries].each do |binary|
  ssh_capture(target.fetch("public_ip"), ssh_options, "test -x #{Shellwords.escape(binary.remote_path)}")
end
ssh_capture(loadgen.fetch("public_ip"), ssh_options, "/usr/local/bin/oha --version")

# Generate the exact mixed-traffic URL file from the deployed benchmark binary.
url_unit = "amber-router-url-generator"
begin
  start_server(target, loadgen, ssh_options, options[:binaries].first, url_unit, options, url_file: true)
  Tempfile.create(["amber-router-urls", ".txt"]) do |file|
    file.close
    scp_capture("root@#{target.fetch("public_ip")}:/opt/amber-router/urls.txt", file.path, ssh_options)
    scp_capture(file.path, "root@#{loadgen.fetch("public_ip")}:/opt/amber-router/urls.txt", ssh_options)
  end
ensure
  stop_server(target, ssh_options, url_unit)
end

url_count = ssh_capture(loadgen.fetch("public_ip"), ssh_options, "wc -l < /opt/amber-router/urls.txt").to_i
abort "Generated URL file is unexpectedly small: #{url_count}" if url_count < 1_000

hardware = {
  "target" => {
    "size" => target.fetch("size"),
    "cpu" => ssh_capture(target.fetch("public_ip"), ssh_options, "lscpu -J"),
    "memory_bytes" => ssh_capture(target.fetch("public_ip"), ssh_options, "awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo").to_i,
    "kernel" => ssh_capture(target.fetch("public_ip"), ssh_options, "uname -a").strip,
  },
  "loadgen" => {
    "size" => loadgen.fetch("size"),
    "cpu" => ssh_capture(loadgen.fetch("public_ip"), ssh_options, "lscpu -J"),
    "memory_bytes" => ssh_capture(loadgen.fetch("public_ip"), ssh_options, "awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo").to_i,
    "kernel" => ssh_capture(loadgen.fetch("public_ip"), ssh_options, "uname -a").strip,
    "oha" => ssh_capture(loadgen.fetch("public_ip"), ssh_options, "/usr/local/bin/oha --version").strip,
  },
}

binaries = options[:binaries].map do |binary|
  metadata = ssh_capture(
    target.fetch("public_ip"),
    ssh_options,
    "printf 'bytes='; stat -c %s #{Shellwords.escape(binary.remote_path)}; printf 'sha256='; sha256sum #{Shellwords.escape(binary.remote_path)} | awk '{print $1}'"
  )
  properties = parse_properties(metadata)
  {
    "name" => binary.name,
    "remote_filename" => File.basename(binary.remote_path),
    "bytes" => properties.fetch("bytes").to_i,
    "sha256" => properties.fetch("sha256"),
  }
end

trials = []
trial_sequence = 0

# Keep each A/B pair temporally close while rotating both binary and load order.
options[:repetitions].times do |repetition_index|
  repetition = repetition_index + 1
  options[:connections].rotate(repetition_index % options[:connections].size).each_with_index do |connections, connection_index|
    rotation = (repetition_index + connection_index) % options[:binaries].size
    options[:binaries].rotate(rotation).each do |binary|
      trial_sequence += 1
      unit = safe_unit_name(binary.name, repetition, connections)
      stem = "#{binary.name}_r#{repetition}_c#{connections}"

      begin
        start_server(target, loadgen, ssh_options, binary, unit, options)
        run_oha(loadgen, ssh_options, connections, options[:warmup], "warmup-#{stem}", measured: false)
        before = unit_stats(target, ssh_options, unit)
        result, loadgen_time = run_oha(loadgen, ssh_options, connections, options[:duration], stem)
        after = unit_stats(target, ssh_options, unit)
        journal = ssh_capture(target.fetch("public_ip"), ssh_options, "journalctl -u #{Shellwords.escape(unit)}.service --no-pager -n 20")

        statuses = result.fetch("statusCodeDistribution")
        raise "#{stem} returned non-200 responses: #{statuses}" unless statuses.keys == ["200"]

        summary = result.fetch("summary")
        total_seconds = summary.fetch("total")
        cpu_before = before.fetch("CPUUsageNSec", "0").to_f
        cpu_after = after.fetch("CPUUsageNSec", "0").to_f
        server_cpu_cores = (cpu_after - cpu_before) / (total_seconds * 1_000_000_000.0)
        loadgen_cpu = loadgen_time.fetch("Percent of CPU this job got", "0%").delete_suffix("%").to_f
        loadgen_rss_kib = loadgen_time.fetch("Maximum resident set size (kbytes)", "0").to_i

        raw_path = File.join(raw_dir, "#{stem}.json")
        File.write(raw_path, JSON.pretty_generate(result))

        trial = {
          "strategy" => binary.name,
          "repetition" => repetition,
          "connections" => connections,
          "trial_sequence" => trial_sequence,
          "requests_per_second" => summary.fetch("requestsPerSec"),
          "average_seconds" => summary.fetch("average"),
          "p50_seconds" => result.fetch("latencyPercentiles").fetch("p50"),
          "p95_seconds" => result.fetch("latencyPercentiles").fetch("p95"),
          "p99_seconds" => result.fetch("latencyPercentiles").fetch("p99"),
          "successful_responses" => statuses.fetch("200"),
          "success_rate" => summary.fetch("successRate"),
          "server_cpu_cores" => server_cpu_cores,
          "requests_per_cpu_second" => summary.fetch("requestsPerSec") / server_cpu_cores,
          "server_memory_current_bytes" => after.fetch("MemoryCurrent", "0").to_i,
          "server_memory_peak_bytes" => after.fetch("MemoryPeak", "0").to_i,
          "server_tasks" => after.fetch("TasksCurrent", "0").to_i,
          "loadgen_cpu_percent" => loadgen_cpu,
          "loadgen_max_rss_bytes" => loadgen_rss_kib * 1024,
          "raw_result" => File.join(File.basename(raw_dir), File.basename(raw_path)),
          "server_log" => journal.lines.map(&:strip).reject(&:empty?),
        }
        trials << trial
        warn format(
          "%s r%d c%d: %.0f RPS, p50 %.1f us, p99 %.1f us, server %.1f%% CPU, %.1f MiB peak",
          binary.name,
          repetition,
          connections,
          trial["requests_per_second"],
          trial["p50_seconds"] * 1_000_000,
          trial["p99_seconds"] * 1_000_000,
          trial["server_cpu_cores"] * 100,
          trial["server_memory_peak_bytes"] / 1_048_576.0
        )
      ensure
        stop_server(target, ssh_options, unit)
      end
    end
  end
end

aggregates = {}
options[:connections].each do |connections|
  aggregates[connections.to_s] = {}
  baseline_median = nil

  options[:binaries].each_with_index do |binary, index|
    rows = trials.select { |trial| trial["strategy"] == binary.name && trial["connections"] == connections }
    rps = summarize(rows.map { |row| row["requests_per_second"] })
    baseline_median = rps["median"] if index.zero?
    aggregates[connections.to_s][binary.name] = {
      "requests_per_second" => rps,
      "p50_seconds" => summarize(rows.map { |row| row["p50_seconds"] }),
      "p99_seconds" => summarize(rows.map { |row| row["p99_seconds"] }),
      "server_cpu_cores" => summarize(rows.map { |row| row["server_cpu_cores"] }),
      "requests_per_cpu_second" => summarize(rows.map { |row| row["requests_per_cpu_second"] }),
      "server_memory_peak_bytes" => summarize(rows.map { |row| row["server_memory_peak_bytes"] }),
      "loadgen_cpu_percent" => summarize(rows.map { |row| row["loadgen_cpu_percent"] }),
      "median_rps_ratio_vs_first_binary" => baseline_median ? rps["median"] / baseline_median : 1.0,
    }
  end
end

paired_comparisons = {}
baseline = options[:binaries].first
options[:connections].each do |connections|
  baseline_rows = trials
    .select { |trial| trial["strategy"] == baseline.name && trial["connections"] == connections }
    .to_h { |trial| [trial["repetition"], trial] }

  paired_comparisons[connections.to_s] = {}
  options[:binaries].drop(1).each do |binary|
    candidate_rows = trials
      .select { |trial| trial["strategy"] == binary.name && trial["connections"] == connections }
      .to_h { |trial| [trial["repetition"], trial] }
    repetitions = baseline_rows.keys & candidate_rows.keys
    rps_ratios = repetitions.map do |repetition|
      candidate_rows.fetch(repetition).fetch("requests_per_second") /
        baseline_rows.fetch(repetition).fetch("requests_per_second")
    end
    efficiency_ratios = repetitions.map do |repetition|
      candidate_rows.fetch(repetition).fetch("requests_per_cpu_second") /
        baseline_rows.fetch(repetition).fetch("requests_per_cpu_second")
    end

    paired_comparisons[connections.to_s][binary.name] = {
      "baseline" => baseline.name,
      "rps_ratio" => summarize(rps_ratios),
      "requests_per_cpu_second_ratio" => summarize(efficiency_ratios),
      "rps_wins" => rps_ratios.count { |ratio| ratio > 1.0 },
      "pair_count" => repetitions.size,
    }
  end
end

payload = {
  "metadata" => {
    "generated_at_utc" => Time.now.utc.iso8601,
    "runner_source_commit" => `git rev-parse HEAD`.strip,
    "binary_source_commit" => options[:binary_source_commit] || `git rev-parse HEAD`.strip,
    "region" => inventory.fetch("region"),
    "vpc_ip_range" => inventory.fetch("vpc").fetch("ip_range"),
    "routes" => options[:routes],
    "traffic_entries" => url_count,
    "traffic_mix" => "45% static, 40% variable, 5% nested, 5% constrained, 3% glob; 70% hot-set; 20% query strings",
    "connections" => options[:connections],
    "duration" => options[:duration],
    "warmup" => options[:warmup],
    "repetitions" => options[:repetitions],
    "trial_schedule" => "paired interleaving with rotating binary and connection order",
    "scope" => "separate DigitalOcean load generator and smallest target Droplet over a private VPC",
    "hardware" => hardware,
    "binaries" => binaries,
  },
  "aggregates" => aggregates,
  "paired_comparisons_vs_first_binary" => paired_comparisons,
  "trials" => trials,
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(payload))
warn "Wrote #{output_path}"
