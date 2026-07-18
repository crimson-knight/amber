#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "shellwords"
require "time"
require_relative "demo_density_round24_support"

ROOT_DIR = File.expand_path("../..", __dir__)

options = {
  densities: [1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 56, 64, 80, 96, 112, 128],
  inventory: nil,
  memory_high: "192M",
  memory_max: "256M",
  output: File.join(ROOT_DIR, "benchmarks", "results", "round24_digitalocean_demo_density.json"),
  port_base: 42_000,
  repetitions: 2,
  routes: 1_000,
  skip_integrity: false,
  ssh_key: File.expand_path("~/.ssh/agentc_droplets_id_ed25519"),
  target_labels: nil,
}

OptionParser.new do |parser|
  parser.banner = "Usage: demo_density_digitalocean.rb --inventory=PATH [options]"
  parser.on("--inventory=PATH", "Provisioned demo-density inventory") { |value| options[:inventory] = File.expand_path(value) }
  parser.on("--densities=LIST", "Comma-separated tenant counts") { |value| options[:densities] = value.split(",").map(&:to_i) }
  parser.on("--targets=LIST", "Comma-separated target labels") { |value| options[:target_labels] = value.split(",") }
  parser.on("--repetitions=COUNT", Integer, "Trials per phase and density") { |value| options[:repetitions] = value }
  parser.on("--routes=COUNT", Integer, "Installed Amber routes per app") { |value| options[:routes] = value }
  parser.on("--skip-integrity", "Skip cloned-database checks for a confirmation-only run") { options[:skip_integrity] = true }
  parser.on("--port-base=PORT", Integer, "First private application port") { |value| options[:port_base] = value }
  parser.on("--memory-high=SIZE", "Per-app systemd MemoryHigh") { |value| options[:memory_high] = value }
  parser.on("--memory-max=SIZE", "Per-app systemd MemoryMax") { |value| options[:memory_max] = value }
  parser.on("--ssh-key=PATH", "Private key for all hosts") { |value| options[:ssh_key] = File.expand_path(value) }
  parser.on("--output=PATH", "Combined result JSON") { |value| options[:output] = File.expand_path(value) }
end.parse!

abort "--inventory is required" unless options[:inventory]
abort "Inventory not found: #{options[:inventory]}" unless File.file?(options[:inventory])
abort "SSH key not found: #{options[:ssh_key]}" unless File.file?(options[:ssh_key])
abort "Densities must be positive and unique" unless options[:densities].all?(&:positive?) && options[:densities].uniq.length == options[:densities].length
abort "At least one repetition is required" unless options[:repetitions].positive?
abort "At most 128 ports are available" if options[:densities].max > 128

phases = [
  {
    "name" => "steady",
    "rate_per_app" => 2.0,
    "warmup_seconds" => 5.0,
    "duration_seconds" => 30.0,
    "request_timeout_seconds" => 5.0,
    "minimum_attainment" => 0.95,
    "maximum_p99_seconds" => 0.250,
    "minimum_fairness" => 0.95,
    "minimum_memory_available_fraction" => 0.05,
  },
  {
    "name" => "burst",
    "rate_per_app" => 10.0,
    "warmup_seconds" => 5.0,
    "duration_seconds" => 20.0,
    "request_timeout_seconds" => 5.0,
    "minimum_attainment" => 0.95,
    "maximum_p99_seconds" => 1.0,
    "minimum_fairness" => 0.90,
    "minimum_memory_available_fraction" => 0.05,
  },
]

def capture!(*command)
  stdout, stderr, status = Open3.capture3(*command)
  return stdout if status.success?

  raise "Command failed (#{status.exitstatus}): #{command.join(' ')}\n#{stderr}\n#{stdout}"
end

def ssh_capture(host, ssh_options, command)
  capture!("ssh", *ssh_options, "root@#{host}", command)
end

def parse_properties(output)
  DemoDensityRound24.parse_properties(output)
end

def numeric(value)
  value.to_s.match?(/\A[0-9]+\z/) ? value.to_i : 0
end

def write_payload(path, payload)
  FileUtils.mkdir_p(File.dirname(path))
  temporary = "#{path}.tmp"
  File.write(temporary, JSON.pretty_generate(payload))
  File.rename(temporary, path)
end

def safe_label(value)
  value.gsub(/[^a-zA-Z0-9_.@-]/, "-")[0, 80]
end

def stop_instances(target, ssh_options)
  ssh_capture(target.fetch("public_ip"), ssh_options, "systemctl stop 'amber-demo-*.service' >/dev/null 2>&1 || true")
end

def prepare_density(target, ssh_options, density)
  command = <<~SHELL
    set -euo pipefail
    seed=/opt/amber-density/seed/benchmark.sqlite3
    root=/opt/amber-density/apps
    reserve=$((1024 * 1024 * 1024))
    mkdir -p "$root"
    for i in $(seq 1 #{density}); do
      app_dir="$root/$i"
      database="$app_dir/benchmark.sqlite3"
      mkdir -p "$app_dir"
      if [[ ! -f "$database" ]]; then
        available=$(df --output=avail -B1 "$root" | tail -n 1 | tr -d ' ')
        seed_bytes=$(stat -c %s "$seed")
        if (( available < seed_bytes + reserve )); then
          printf 'status=insufficient_storage\navailable_bytes=%s\nseed_bytes=%s\n' "$available" "$seed_bytes"
          exit 0
        fi
        cp --reflink=auto --sparse=always "$seed" "$database"
      fi
      rm -f "$database-wal" "$database-shm"
      sqlite3 "$database" "PRAGMA busy_timeout=5000; DELETE FROM benchmark_sessions WHERE token_hash <> '7b529f08962dc96604dc0a21320eaa5f971f3a4ee36369569246bd13e9ff8133'; DELETE FROM benchmark_resource_events; PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null
    done
    sync
    printf 'status=ok\navailable_bytes=%s\nseed_bytes=%s\n' \
      "$(df --output=avail -B1 "$root" | tail -n 1 | tr -d ' ')" \
      "$(stat -c %s "$seed")"
  SHELL
  parse_properties(ssh_capture(target.fetch("public_ip"), ssh_options, command))
end

def start_instances(target, loadgen, ssh_options, density, options)
  commands = (1..density).map do |index|
    unit = "amber-demo-#{safe_label(target.fetch('label'))}-#{index}"
    port = options.fetch(:port_base) + index - 1
    database_url = "sqlite3:/opt/amber-density/apps/#{index}/benchmark.sqlite3?initial_pool_size=0&max_pool_size=8&max_idle_pool_size=8&checkout_timeout=5.0"
    [
      "systemd-run", "--quiet", "--collect", "--unit=#{unit}",
      "--property=CPUAccounting=yes", "--property=MemoryAccounting=yes", "--property=IOAccounting=yes",
      "--property=CPUWeight=100", "--property=CPUQuota=100%", "--property=IOWeight=100",
      "--property=MemoryHigh=#{options.fetch(:memory_high)}", "--property=MemoryMax=#{options.fetch(:memory_max)}",
      "--property=TasksMax=128",
      "--setenv=DATABASE_URL=#{database_url}", "--setenv=SQLITE_SYNCHRONOUS=FULL",
      "/opt/amber-density/bin/stock_sqlite",
      "--host=#{target.fetch('private_ip')}", "--port=#{port}", "--routes=#{options.fetch(:routes)}",
    ].map { |part| Shellwords.escape(part) }.join(" ")
  end
  ssh_capture(target.fetch("public_ip"), ssh_options, commands.join("\n"))

  readiness = <<~SHELL
    set -euo pipefail
    for port in $(seq #{options.fetch(:port_base)} #{options.fetch(:port_base) + density - 1}); do
      ready=0
      for _ in $(seq 1 300); do
        body=$(curl -fsS --max-time 1 "http://#{target.fetch('private_ip')}:$port/benchmark/health" 2>/dev/null || true)
        case "$body" in
          *'"status":"ok"'*'"database":"sqlite"'*) ready=1; break ;;
        esac
        sleep 0.1
      done
      if [[ "$ready" != "1" ]]; then
        echo "Application on port $port did not become ready" >&2
        exit 1
      fi
    done
  SHELL
  ssh_capture(loadgen.fetch("public_ip"), ssh_options, readiness)
end

def proc_snapshot(target, ssh_options)
  output = ssh_capture(target.fetch("public_ip"), ssh_options, <<~'SHELL')
    root_source=$(findmnt -no SOURCE /)
    device=${root_source##*/}
    printf 'device=%s\n' "$device"
    awk '/^cpu / {printf "cpu=%s\n", substr($0, 5)}' /proc/stat
    awk -v d="$device" '$3 == d {printf "disk=%s %s %s %s %s %s %s %s %s %s %s\n", $4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14}' /proc/diskstats
    awk '/^(pgfault|pgmajfault|pswpin|pswpout|oom_kill) / {printf "%s=%s\n", $1, $2}' /proc/vmstat
    awk '/^(MemTotal|MemAvailable|SwapTotal|SwapFree):/ {printf "%s=%s\n", $1, $2 * 1024}' /proc/meminfo
    printf 'loadavg=%s\n' "$(cat /proc/loadavg)"
  SHELL
  properties = parse_properties(output)
  properties["cpu"] = properties.fetch("cpu").split.map(&:to_i)
  properties["disk"] = properties.fetch("disk", "0 0 0 0 0 0 0 0 0 0 0").split.map(&:to_i)
  %w[pgfault pgmajfault pswpin pswpout oom_kill MemTotal MemAvailable SwapTotal SwapFree].each do |key|
    properties[key] = numeric(properties.fetch(key, "0"))
  end
  properties
end

def unit_snapshot(target, ssh_options, density)
  units = (1..density).map { |index| "amber-demo-#{safe_label(target.fetch('label'))}-#{index}" }
  properties = %w[
    ActiveState SubState Result ExecMainStatus OOMKilled
    CPUUsageNSec MemoryCurrent MemoryPeak TasksCurrent IOReadBytes IOWriteBytes
  ].map { |property| "--property=#{property}" }.join(" ")
  command = units.map do |unit|
    "printf '__UNIT__=%s\\n' #{Shellwords.escape(unit)}; systemctl show #{Shellwords.escape(unit)}.service --no-pager #{properties}"
  end.join("\n")
  output = ssh_capture(target.fetch("public_ip"), ssh_options, command)
  rows = {}
  current = nil
  output.each_line do |line|
    if line.start_with?("__UNIT__=")
      current = line.split("=", 2).last.strip
      rows[current] = {}
    elsif current
      key, value = line.strip.split("=", 2)
      rows[current][key] = value if key && value
    end
  end
  rows
end

def telemetry_delta(before_proc, after_proc, before_units, after_units, elapsed)
  cpu_delta = after_proc.fetch("cpu").zip(before_proc.fetch("cpu")).map { |right, left| right - left }
  cpu_total = cpu_delta.sum.to_f
  idle = cpu_delta.fetch(3, 0) + cpu_delta.fetch(4, 0)
  steal = cpu_delta.fetch(7, 0)
  disk_delta = after_proc.fetch("disk").zip(before_proc.fetch("disk")).map { |right, left| right - left }
  unit_names = after_units.keys
  cpu_usage_seconds = unit_names.sum do |unit|
    (numeric(after_units.dig(unit, "CPUUsageNSec")) - numeric(before_units.dig(unit, "CPUUsageNSec"))) / 1_000_000_000.0
  end
  oom_kills = (after_proc.fetch("oom_kill") - before_proc.fetch("oom_kill")) + unit_names.count do |unit|
    after_units.dig(unit, "OOMKilled") == "yes"
  end
  memory_total = after_proc.fetch("MemTotal")

  {
    "target_cpu_utilization" => cpu_total.zero? ? 0.0 : (cpu_total - idle - steal) / cpu_total,
    "cpu_iowait_fraction" => cpu_total.zero? ? 0.0 : cpu_delta.fetch(4, 0) / cpu_total,
    "cpu_steal_fraction" => cpu_total.zero? ? 0.0 : steal / cpu_total,
    "application_cpu_cores" => elapsed.zero? ? 0.0 : cpu_usage_seconds / elapsed,
    "disk_read_bytes" => disk_delta.fetch(2, 0) * 512,
    "disk_write_bytes" => disk_delta.fetch(6, 0) * 512,
    "disk_busy_seconds" => disk_delta.fetch(9, 0) / 1_000.0,
    "disk_utilization" => elapsed.zero? ? 0.0 : (disk_delta.fetch(9, 0) / 1_000.0) / elapsed,
    "page_faults" => after_proc.fetch("pgfault") - before_proc.fetch("pgfault"),
    "major_page_faults" => after_proc.fetch("pgmajfault") - before_proc.fetch("pgmajfault"),
    "swap_in_pages" => after_proc.fetch("pswpin") - before_proc.fetch("pswpin"),
    "swap_out_pages" => after_proc.fetch("pswpout") - before_proc.fetch("pswpout"),
    "swap_total_bytes" => after_proc.fetch("SwapTotal"),
    "memory_available_bytes" => after_proc.fetch("MemAvailable"),
    "memory_available_fraction" => memory_total.zero? ? 0.0 : after_proc.fetch("MemAvailable") / memory_total.to_f,
    "application_memory_current_bytes" => unit_names.sum { |unit| numeric(after_units.dig(unit, "MemoryCurrent")) },
    "application_memory_peak_bytes" => unit_names.sum { |unit| numeric(after_units.dig(unit, "MemoryPeak")) },
    "all_units_active" => unit_names.length == before_units.length && unit_names.all? { |unit| after_units.dig(unit, "ActiveState") == "active" },
    "oom_kills" => oom_kills,
    "unit_states" => after_units,
    "loadavg_after" => after_proc.fetch("loadavg"),
  }
end

def run_load(loadgen, target, ssh_options, density, phase, options, seed)
  hosts = (1..density).map do |index|
    "http://#{target.fetch('private_ip')}:#{options.fetch(:port_base) + index - 1}"
  end
  command = [
    "ruby", "/opt/amber-density/load/demo_density_fixed_rate.rb",
    "--hosts=#{hosts.join(',')}",
    "--rate-per-app=#{phase.fetch('rate_per_app')}",
    "--warmup=#{phase.fetch('warmup_seconds')}",
    "--duration=#{phase.fetch('duration_seconds')}",
    "--timeout=#{phase.fetch('request_timeout_seconds')}",
    "--seed=#{seed}",
  ].map { |part| Shellwords.escape(part) }.join(" ")
  JSON.parse(ssh_capture(loadgen.fetch("public_ip"), ssh_options, command))
end

def hardware_metadata(target, ssh_options)
  host = target.fetch("public_ip")
  fio = ssh_capture(host, ssh_options, <<~'SHELL')
    fio --name=amber-r24-disk --filename=/opt/amber-density/seed/fio-probe.bin --size=128m --direct=1 --ioengine=libaio --rw=randrw --rwmixread=70 --bs=4k --iodepth=16 --runtime=10 --time_based --group_reporting --output-format=json
  SHELL
  ssh_capture(host, ssh_options, "rm -f /opt/amber-density/seed/fio-probe.bin; sync; echo 3 > /proc/sys/vm/drop_caches")
  {
    "cpu" => JSON.parse(ssh_capture(host, ssh_options, "lscpu -J")),
    "memory_bytes" => ssh_capture(host, ssh_options, "awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo").to_i,
    "swap_bytes" => ssh_capture(host, ssh_options, "awk '/SwapTotal/ {print $2 * 1024}' /proc/meminfo").to_i,
    "kernel" => ssh_capture(host, ssh_options, "uname -a").strip,
    "disk" => JSON.parse(ssh_capture(host, ssh_options, "lsblk -J -b -o NAME,SIZE,TYPE,MOUNTPOINTS,ROTA,MODEL")),
    "fio" => JSON.parse(fio),
  }
end

inventory = JSON.parse(File.read(options.fetch(:inventory)))
loadgen = inventory.fetch("resources").fetch("loadgen")
targets = inventory.fetch("resources").fetch("targets")
if options[:target_labels]
  targets = options.fetch(:target_labels).map do |label|
    targets.find { |target| target.fetch("label") == label } || abort("Unknown target label: #{label}")
  end
end

known_hosts = "/tmp/#{inventory.fetch('prefix')}-density-runner-known-hosts"
FileUtils.touch(known_hosts)
ssh_options = [
  "-i", options.fetch(:ssh_key),
  "-o", "BatchMode=yes",
  "-o", "ConnectTimeout=10",
  "-o", "StrictHostKeyChecking=accept-new",
  "-o", "UserKnownHostsFile=#{known_hosts}",
]

targets.each do |target|
  ssh_capture(target.fetch("public_ip"), ssh_options, "test -x /opt/amber-density/bin/stock_sqlite && test $(awk '/SwapTotal/ {print $2}' /proc/meminfo) -eq 0")
end
ssh_capture(loadgen.fetch("public_ip"), ssh_options, "test -x /opt/amber-density/load/demo_density_fixed_rate.rb")

metadata_targets = targets.map do |target|
  target.slice("label", "cpu_class", "size", "vcpus", "memory_mb", "disk_gb", "price_monthly", "price_hourly").merge(
    "hardware" => hardware_metadata(target, ssh_options)
  )
end

payload = {
  "metadata" => {
    "generated_at_utc" => Time.now.utc.iso8601,
    "source_commit" => capture!("git", "-C", ROOT_DIR, "rev-parse", "HEAD").strip,
    "inventory" => File.basename(options.fetch(:inventory)),
    "region" => inventory.fetch("region"),
    "route_count_per_app" => options.fetch(:routes),
    "users_per_app" => 10_000,
    "resources_per_app" => 1_000_000,
    "database" => "one private SQLite WAL database per app with synchronous=FULL",
    "database_pool" => "Grant pool capped at 8 connections and opened on demand",
    "systemd_isolation" => {
      "CPUWeight" => 100,
      "CPUQuota" => "100%",
      "IOWeight" => 100,
      "MemoryHigh" => options.fetch(:memory_high),
      "MemoryMax" => options.fetch(:memory_max),
      "TasksMax" => 128,
    },
    "densities" => options.fetch(:densities),
    "repetitions" => options.fetch(:repetitions),
    "phases" => phases,
    "capacity_definition" => "all phase repetitions pass request, latency, fairness, process, OOM, swap, and memory-reserve gates",
    "load_generator" => loadgen.slice("size", "region").merge(
      "cpu" => JSON.parse(ssh_capture(loadgen.fetch("public_ip"), ssh_options, "lscpu -J")),
      "kernel" => ssh_capture(loadgen.fetch("public_ip"), ssh_options, "uname -a").strip
    ),
    "targets" => metadata_targets,
  },
  "capacity_events" => [],
  "trials" => [],
  "summary" => {},
}

output_path = options.fetch(:output)
write_payload(output_path, payload)
exhausted_targets = {}

options.fetch(:densities).each_with_index do |density, density_index|
  targets.rotate(density_index % targets.length).each do |target|
    label = target.fetch("label")
    next if exhausted_targets[label]

    warn "Preparing #{label} at density #{density}"
    begin
      stop_instances(target, ssh_options)
      preparation = prepare_density(target, ssh_options, density)
      if preparation.fetch("status") != "ok"
        payload.fetch("capacity_events") << {
          "target" => label,
          "density" => density,
          "status" => preparation.fetch("status"),
          "details" => preparation,
        }
        exhausted_targets[label] = true
        write_payload(output_path, payload)
        next
      end

      start_instances(target, loadgen, ssh_options, density, options)
      density_trials = []
      options.fetch(:repetitions).times do |repetition_index|
        phases.rotate(repetition_index % phases.length).each do |phase|
          before_proc = proc_snapshot(target, ssh_options)
          before_units = unit_snapshot(target, ssh_options, density)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          load_result = run_load(
            loadgen, target, ssh_options, density, phase, options,
            24_024 + density * 1_000 + repetition_index * 100
          )
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          after_proc = proc_snapshot(target, ssh_options)
          after_units = unit_snapshot(target, ssh_options, density)
          telemetry = telemetry_delta(before_proc, after_proc, before_units, after_units, elapsed)
          gate = DemoDensityRound24.evaluate_trial(load_result, telemetry, phase)
          trial = {
            "target" => label,
            "cpu_class" => target.fetch("cpu_class"),
            "size" => target.fetch("size"),
            "density" => density,
            "phase" => phase.fetch("name"),
            "repetition" => repetition_index + 1,
            "sequence" => payload.fetch("trials").length + 1,
            "load" => load_result,
            "telemetry" => telemetry,
            "gate" => gate,
          }
          payload.fetch("trials") << trial
          density_trials << trial
          write_payload(output_path, payload)
          warn format(
            "%-14s n=%-2d %-6s r%d: %6.1f/%6.1f RPS p99 %6.1f ms fairness %.3f steal %5.2f%% mem %5.1f MiB %s",
            label,
            density,
            phase.fetch("name"),
            repetition_index + 1,
            load_result.dig("overall", "success_rps"),
            load_result.dig("overall", "target_rps"),
            load_result.dig("overall", "p99_seconds") * 1_000,
            load_result.dig("overall", "fairness"),
            telemetry.fetch("cpu_steal_fraction") * 100,
            telemetry.fetch("memory_available_bytes") / 1_048_576.0,
            gate.fetch("passed") ? "PASS" : "FAIL: #{gate.fetch('failure_reasons').join(', ')}"
          )
        end
      end

      expected_trials = options.fetch(:repetitions) * phases.length
      density_passed = density_trials.length == expected_trials && density_trials.all? { |trial| trial.dig("gate", "passed") }
      payload.fetch("capacity_events") << {
        "target" => label,
        "density" => density,
        "status" => density_passed ? "passed" : "failed",
        "failure_reasons" => density_trials.flat_map { |trial| trial.dig("gate", "failure_reasons") }.uniq.sort,
      }
      exhausted_targets[label] = true unless density_passed
      payload["summary"] = DemoDensityRound24.build_summary(payload)
      write_payload(output_path, payload)
    rescue StandardError => error
      payload.fetch("capacity_events") << {
        "target" => label,
        "density" => density,
        "status" => "infrastructure_error",
        "error" => "#{error.class}: #{error.message}",
      }
      exhausted_targets[label] = true
      write_payload(output_path, payload)
      warn "#{label} density #{density} stopped: #{error.class}: #{error.message}"
    ensure
      stop_instances(target, ssh_options)
    end
  end
end

integrity = if options.fetch(:skip_integrity)
              targets.to_h { |target| [target.fetch("label"), {"skipped" => true, "reason" => "confirmation-only run"}] }
            else
              targets.map do |target|
                Thread.new do
                  output = ssh_capture(target.fetch("public_ip"), ssh_options, <<~'SHELL')
                    set -euo pipefail
                    failures=0
                    checked=0
                    for database in /opt/amber-density/apps/*/benchmark.sqlite3; do
                      [[ -f "$database" ]] || continue
                      checked=$((checked + 1))
                      result=$(sqlite3 "$database" 'PRAGMA quick_check;')
                      [[ "$result" == "ok" ]] || failures=$((failures + 1))
                    done
                    printf 'checked=%s\nfailures=%s\n' "$checked" "$failures"
                  SHELL
                  [target.fetch("label"), parse_properties(output).transform_values(&:to_i)]
                end
              end.map(&:value).to_h
            end

payload["summary"] = DemoDensityRound24.build_summary(payload)
payload["metadata"]["integrity_checks"] = integrity
payload["metadata"]["completed_at_utc"] = Time.now.utc.iso8601
write_payload(output_path, payload)
puts "Wrote #{output_path} with #{payload.fetch('trials').length} trials"
