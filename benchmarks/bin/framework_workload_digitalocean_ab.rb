#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "shellwords"
require "time"

Variant = Struct.new(:name, :remote_path, :script_path, keyword_init: true)

options = {
  binary_source_commit: nil,
  connections: [16],
  duration: "15s",
  inventory: nil,
  output: "benchmarks/results/round22_digitalocean_framework_workload.json",
  port: 41_019,
  repetitions: 9,
  routes: 1_000,
  ssh_key: File.expand_path("~/.ssh/agentc_droplets_id_ed25519"),
  threads: 4,
  variants: [],
  warmup: "5s",
}

OptionParser.new do |parser|
  parser.banner = "Usage: framework_workload_digitalocean_ab.rb --inventory=PATH --variant=NAME:REMOTE_BINARY:LOCAL_WRK_SCRIPT [options]"
  parser.on("--inventory=PATH", "Provisioned lab inventory JSON") { |value| options[:inventory] = File.expand_path(value) }
  parser.on("--variant=NAME:BINARY:SCRIPT", "Strategy, target executable, and local wrk script (repeatable)") do |value|
    name, remote_path, script_path = value.split(":", 3)
    raise OptionParser::InvalidArgument, value unless name && remote_path && script_path
    options[:variants] << Variant.new(name: name, remote_path: remote_path, script_path: File.expand_path(script_path))
  end
  parser.on("--binary-source-commit=SHA", "Commit used to compile the deployed binaries") { |value| options[:binary_source_commit] = value }
  parser.on("--connections=LIST", "Comma-separated connection counts") { |value| options[:connections] = value.split(",").map(&:to_i) }
  parser.on("--duration=TIME", "Measured duration per trial") { |value| options[:duration] = value }
  parser.on("--warmup=TIME", "Warmup duration per trial") { |value| options[:warmup] = value }
  parser.on("--repetitions=COUNT", Integer, "Rotated process repetitions") { |value| options[:repetitions] = value }
  parser.on("--routes=COUNT", Integer, "Routes installed on the target") { |value| options[:routes] = value }
  parser.on("--threads=COUNT", Integer, "wrk load-generator threads") { |value| options[:threads] = value }
  parser.on("--port=PORT", Integer, "Private benchmark port") { |value| options[:port] = value }
  parser.on("--ssh-key=PATH", "Private key used for both hosts") { |value| options[:ssh_key] = File.expand_path(value) }
  parser.on("--output=PATH", "Combined result JSON") { |value| options[:output] = File.expand_path(value) }
end.parse!

abort "--inventory is required" unless options[:inventory]
abort "At least two --variant entries are required" if options[:variants].size < 2
abort "Inventory not found: #{options[:inventory]}" unless File.file?(options[:inventory])
abort "SSH private key not found: #{options[:ssh_key]}" unless File.file?(options[:ssh_key])
options[:variants].each do |variant|
  abort "wrk script not found: #{variant.script_path}" unless File.file?(variant.script_path)
end

inventory = JSON.parse(File.read(options[:inventory]))
target = inventory.fetch("resources").fetch("target")
loadgen = inventory.fetch("resources").fetch("loadgen")
known_hosts = "/tmp/#{inventory.fetch("prefix")}-framework-runner-known-hosts"
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

def seconds(value)
  match = value.to_s.strip.match(/\A([0-9.]+)(us|ms|s|m|h)\z/)
  raise "Unable to parse duration: #{value.inspect}" unless match

  number = match[1].to_f
  case match[2]
  when "us" then number / 1_000_000.0
  when "ms" then number / 1_000.0
  when "s"  then number
  when "m"  then number * 60.0
  when "h"  then number * 3_600.0
  end
end

def parse_wrk(output)
  requests_per_second = output[/Requests\/sec:\s+([0-9.]+)/, 1]
  total_match = output.match(/([0-9]+) requests in ([0-9.]+(?:us|ms|s|m|h)),/)
  p50 = output[/^\s*50%\s+([0-9.]+(?:us|ms|s|m|h))\s*$/i, 1]
  p99 = output[/^\s*99%\s+([0-9.]+(?:us|ms|s|m|h))\s*$/i, 1]
  raise "Unable to parse wrk output:\n#{output}" unless requests_per_second && total_match && p50 && p99

  socket_errors = if line = output[/Socket errors:\s+connect ([0-9]+), read ([0-9]+), write ([0-9]+), timeout ([0-9]+)/, 0]
                    line.scan(/[0-9]+/).map(&:to_i).sum
                  else
                    0
                  end
  non_2xx = (output[/Non-2xx or 3xx responses:\s+([0-9]+)/, 1] || "0").to_i
  {
    "requests_per_second" => requests_per_second.to_f,
    "total_requests" => total_match[1].to_i,
    "elapsed_seconds" => seconds(total_match[2]),
    "p50_seconds" => seconds(p50),
    "p99_seconds" => seconds(p99),
    "socket_errors" => socket_errors,
    "non_2xx_responses" => non_2xx,
  }
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
  strategy_name = strategy.gsub(/[^a-zA-Z0-9]+/, "-").downcase
  "amber-framework-#{strategy_name}-r#{repetition}-c#{connections}"
end

def start_server(target, loadgen, ssh_options, variant, unit, options)
  args = [
    variant.remote_path,
    "--server",
    "--host=#{target.fetch("private_ip")}",
    "--port=#{options.fetch(:port)}",
    "--routes=#{options.fetch(:routes)}",
  ]
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

def run_wrk(loadgen, target, ssh_options, script_path, connections, duration, threads, port, output_stem, measured: true)
  time_path = "/tmp/#{output_stem}.time.txt"
  url = "http://#{target.fetch("private_ip")}:#{port}"
  command = [
    "wrk", "--threads", threads.to_s, "--connections", connections.to_s,
    "--duration", duration, "--latency", "--script", script_path, url,
  ].map { |value| Shellwords.escape(value) }.join(" ")

  if measured
    remote = "LC_ALL=C /usr/bin/time -v -o #{Shellwords.escape(time_path)} #{command} && printf '\n---TIME---\n' && cat #{Shellwords.escape(time_path)}"
    output = ssh_capture(loadgen.fetch("public_ip"), ssh_options, remote)
    wrk_output, timing = output.split("\n---TIME---\n", 2)
    [parse_wrk(wrk_output), parse_time_verbose(timing || ""), wrk_output]
  else
    ssh_capture(loadgen.fetch("public_ip"), ssh_options, "#{command} >/dev/null")
    nil
  end
end

output_path = File.expand_path(options[:output])
raw_dir = output_path.sub(/\.json\z/, "_raw")
FileUtils.mkdir_p(raw_dir)

options[:variants].each do |variant|
  ssh_capture(target.fetch("public_ip"), ssh_options, "test -x #{Shellwords.escape(variant.remote_path)}")
end
ssh_capture(loadgen.fetch("public_ip"), ssh_options, "command -v wrk")
ssh_capture(loadgen.fetch("public_ip"), ssh_options, "mkdir -p /opt/amber-router/workloads")

remote_scripts = {}
options[:variants].each do |variant|
  remote_path = "/opt/amber-router/workloads/#{variant.name}.lua"
  scp_capture(variant.script_path, "root@#{loadgen.fetch("public_ip")}:#{remote_path}", ssh_options)
  remote_scripts[variant.name] = remote_path
end

request_tables = options[:variants].map do |variant|
  lines = File.readlines(variant.script_path)
  start = lines.index { |line| line.start_with?("local requests =") }
  abort "Missing request table in #{variant.script_path}" unless start
  Digest::SHA256.hexdigest(lines[start..-1].join)
end
abort "Workload request sequences differ across variants" unless request_tables.uniq.size == 1

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
    "wrk" => ssh_capture(loadgen.fetch("public_ip"), ssh_options, "wrk -v 2>&1 || true").lines.first.to_s.strip,
  },
}

binary_metadata = options[:variants].map do |variant|
  metadata = ssh_capture(
    target.fetch("public_ip"),
    ssh_options,
    "printf 'bytes='; stat -c %s #{Shellwords.escape(variant.remote_path)}; printf 'sha256='; sha256sum #{Shellwords.escape(variant.remote_path)} | awk '{print $1}'"
  )
  properties = parse_properties(metadata)
  {
    "name" => variant.name,
    "remote_filename" => File.basename(variant.remote_path),
    "bytes" => properties.fetch("bytes").to_i,
    "sha256" => properties.fetch("sha256"),
    "wrk_script_bytes" => File.size(variant.script_path),
    "wrk_script_sha256" => Digest::SHA256.file(variant.script_path).hexdigest,
  }
end

trials = []
trial_sequence = 0
options[:repetitions].times do |repetition_index|
  repetition = repetition_index + 1
  options[:connections].rotate(repetition_index % options[:connections].size).each_with_index do |connections, scenario_index|
    rotation = (repetition_index + scenario_index) % options[:variants].size
    options[:variants].rotate(rotation).each do |variant|
      trial_sequence += 1
      unit = safe_unit_name(variant.name, repetition, connections)
      stem = "#{variant.name}_r#{repetition}_c#{connections}"
      begin
        start_server(target, loadgen, ssh_options, variant, unit, options)
        run_wrk(loadgen, target, ssh_options, remote_scripts.fetch(variant.name), connections, options[:warmup], options[:threads], options[:port], "warmup-#{stem}", measured: false)
        before = unit_stats(target, ssh_options, unit)
        result, loadgen_time, raw_output = run_wrk(
          loadgen,
          target,
          ssh_options,
          remote_scripts.fetch(variant.name),
          connections,
          options[:duration],
          options[:threads],
          options[:port],
          stem
        )
        after = unit_stats(target, ssh_options, unit)
        raise "#{stem} had #{result.fetch("socket_errors")} socket errors" unless result.fetch("socket_errors").zero?
        raise "#{stem} had #{result.fetch("non_2xx_responses")} non-2xx responses" unless result.fetch("non_2xx_responses").zero?

        cpu_before = before.fetch("CPUUsageNSec", "0").to_f
        cpu_after = after.fetch("CPUUsageNSec", "0").to_f
        server_cpu_cores = (cpu_after - cpu_before) / (result.fetch("elapsed_seconds") * 1_000_000_000.0)
        loadgen_cpu = loadgen_time.fetch("Percent of CPU this job got", "0%").delete_suffix("%").to_f
        raw_path = File.join(raw_dir, "#{stem}.txt")
        File.write(raw_path, raw_output)
        journal = ssh_capture(target.fetch("public_ip"), ssh_options, "journalctl -u #{Shellwords.escape(unit)}.service --no-pager -n 20")
        trial = result.merge(
          "strategy" => variant.name,
          "repetition" => repetition,
          "connections" => connections,
          "trial_sequence" => trial_sequence,
          "server_cpu_cores" => server_cpu_cores,
          "requests_per_cpu_second" => result.fetch("requests_per_second") / server_cpu_cores,
          "server_memory_current_bytes" => after.fetch("MemoryCurrent", "0").to_i,
          "server_memory_peak_bytes" => after.fetch("MemoryPeak", "0").to_i,
          "server_tasks" => after.fetch("TasksCurrent", "0").to_i,
          "loadgen_cpu_percent" => loadgen_cpu,
          "loadgen_max_rss_bytes" => loadgen_time.fetch("Maximum resident set size (kbytes)", "0").to_i * 1024,
          "raw_result" => File.join(File.basename(raw_dir), File.basename(raw_path)),
          "server_log" => journal.lines.map(&:strip).reject(&:empty?)
        )
        trials << trial
        warn format(
          "%s r%d c%d: %.0f RPS, p50 %.1f us, p99 %.1f us, server %.1f%% CPU, %.1f MiB peak",
          variant.name,
          repetition,
          connections,
          trial.fetch("requests_per_second"),
          trial.fetch("p50_seconds") * 1_000_000,
          trial.fetch("p99_seconds") * 1_000_000,
          trial.fetch("server_cpu_cores") * 100,
          trial.fetch("server_memory_peak_bytes") / 1_048_576.0
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
  options[:variants].each_with_index do |variant, index|
    rows = trials.select { |trial| trial.fetch("strategy") == variant.name && trial.fetch("connections") == connections }
    rps = summarize(rows.map { |row| row.fetch("requests_per_second") })
    baseline_median = rps.fetch("median") if index.zero?
    aggregates[connections.to_s][variant.name] = {
      "requests_per_second" => rps,
      "p50_seconds" => summarize(rows.map { |row| row.fetch("p50_seconds") }),
      "p99_seconds" => summarize(rows.map { |row| row.fetch("p99_seconds") }),
      "server_cpu_cores" => summarize(rows.map { |row| row.fetch("server_cpu_cores") }),
      "requests_per_cpu_second" => summarize(rows.map { |row| row.fetch("requests_per_cpu_second") }),
      "server_memory_peak_bytes" => summarize(rows.map { |row| row.fetch("server_memory_peak_bytes") }),
      "median_rps_ratio_vs_first_variant" => rps.fetch("median") / baseline_median,
    }
  end
end

paired = {}
baseline = options[:variants].first
options[:connections].each do |connections|
  baseline_rows = trials
    .select { |trial| trial.fetch("strategy") == baseline.name && trial.fetch("connections") == connections }
    .each_with_object({}) { |trial, result| result[trial.fetch("repetition")] = trial }
  paired[connections.to_s] = {}
  options[:variants].drop(1).each do |variant|
    candidate_rows = trials
      .select { |trial| trial.fetch("strategy") == variant.name && trial.fetch("connections") == connections }
      .each_with_object({}) { |trial, result| result[trial.fetch("repetition")] = trial }
    repetitions = baseline_rows.keys & candidate_rows.keys
    rps_ratios = repetitions.map do |repetition|
      candidate_rows.fetch(repetition).fetch("requests_per_second") / baseline_rows.fetch(repetition).fetch("requests_per_second")
    end
    efficiency_ratios = repetitions.map do |repetition|
      candidate_rows.fetch(repetition).fetch("requests_per_cpu_second") / baseline_rows.fetch(repetition).fetch("requests_per_cpu_second")
    end
    paired[connections.to_s][variant.name] = {
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
    "route_mix" => "45% static; 25% REST ID; 15% dynamic action; 5% nested; 5% constrained; 5% glob",
    "method_mix" => "65% GET; 20% POST; 8% PUT; 5% PATCH; 2% DELETE",
    "sampled_methods" => {"GET" => 2665, "POST" => 820, "PUT" => 328, "PATCH" => 203, "DELETE" => 80},
    "sampled_route_shapes" => {"static" => 1844, "restful" => 1024, "variable" => 613, "nested" => 205, "constrained" => 205, "glob" => 205},
    "traffic_entries" => 4096,
    "traffic_locality" => "70% selects the first 20% within each method-and-route-shape cell; 20% query strings",
    "request_table_sha256" => request_tables.first,
    "connections" => options[:connections],
    "threads" => options[:threads],
    "duration" => options[:duration],
    "warmup" => options[:warmup],
    "repetitions" => options[:repetitions],
    "trial_schedule" => "paired interleaving with rotating variant and connection order",
    "scope" => "separate DigitalOcean load generator and smallest target Droplet over a private VPC using HTTP/1.1 keep-alive",
    "hardware" => hardware,
    "binaries" => binary_metadata,
  },
  "aggregates" => aggregates,
  "paired_comparisons_vs_first_variant" => paired,
  "trials" => trials,
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(payload))
warn "Wrote #{output_path}"
