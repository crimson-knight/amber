#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "shellwords"
require "time"

Variant = Struct.new(:name, :binary, :database, :sqlite_sync, keyword_init: true)
Scenario = Struct.new(:name, :script, :dynamic_session, keyword_init: true)

ROOT_DIR = File.expand_path("../..", __dir__)
DATABASE_DIR = File.join(ROOT_DIR, "benchmarks", "database")

options = {
  cold_cache: false,
  compiler: "stock",
  connections: [16],
  duration: "12s",
  inventory: nil,
  output: File.join(ROOT_DIR, "benchmarks", "results", "round23_digitalocean_database_matrix.json"),
  port: 41_023,
  repetitions: 7,
  routes: 1_000,
  scenario_names: %w[login read_hot read_broad mixed_journey crud_cycle],
  ssh_key: File.expand_path("~/.ssh/agentc_droplets_id_ed25519"),
  timeout: "10s",
  variant_names: %w[postgres sqlite_full sqlite_normal],
  warmup: "6s",
}

OptionParser.new do |parser|
  parser.banner = "Usage: database_digitalocean_matrix.rb --inventory=PATH [options]"
  parser.on("--cold-cache", "Drop database and OS caches and skip warmup") { options[:cold_cache] = true }
  parser.on("--inventory=PATH", "Provisioned database-lab inventory") { |value| options[:inventory] = File.expand_path(value) }
  parser.on("--compiler=NAME", "stock or acrystal") { |value| options[:compiler] = value }
  parser.on("--connections=LIST", "Comma-separated connection counts") { |value| options[:connections] = value.split(",").map(&:to_i) }
  parser.on("--duration=TIME", "Measured duration per trial") { |value| options[:duration] = value }
  parser.on("--warmup=TIME", "Warmup duration per trial") { |value| options[:warmup] = value }
  parser.on("--repetitions=COUNT", Integer, "Rotated process repetitions") { |value| options[:repetitions] = value }
  parser.on("--routes=COUNT", Integer, "Routes installed in Amber") { |value| options[:routes] = value }
  parser.on("--port=PORT", Integer, "Private benchmark port") { |value| options[:port] = value }
  parser.on("--variants=LIST", "postgres,sqlite_full,sqlite_normal") { |value| options[:variant_names] = value.split(",") }
  parser.on("--scenarios=LIST", "login,read_hot,read_broad,mixed_journey,crud_cycle") { |value| options[:scenario_names] = value.split(",") }
  parser.on("--ssh-key=PATH", "Private key for both hosts") { |value| options[:ssh_key] = File.expand_path(value) }
  parser.on("--timeout=TIME", "Per-request wrk socket timeout") { |value| options[:timeout] = value }
  parser.on("--output=PATH", "Combined result JSON") { |value| options[:output] = File.expand_path(value) }
end.parse!

abort "--inventory is required" unless options[:inventory]
abort "Inventory not found: #{options[:inventory]}" unless File.file?(options[:inventory])
abort "SSH key not found: #{options[:ssh_key]}" unless File.file?(options[:ssh_key])
abort "--compiler must be stock or acrystal" unless %w[stock acrystal].include?(options[:compiler])

all_variants = {
  "postgres" => Variant.new(
    name: "postgres",
    binary: "/opt/amber-database/bin/#{options[:compiler]}_postgres",
    database: "postgresql",
    sqlite_sync: nil
  ),
  "sqlite_full" => Variant.new(
    name: "sqlite_full",
    binary: "/opt/amber-database/bin/#{options[:compiler]}_sqlite",
    database: "sqlite",
    sqlite_sync: "FULL"
  ),
  "sqlite_normal" => Variant.new(
    name: "sqlite_normal",
    binary: "/opt/amber-database/bin/#{options[:compiler]}_sqlite",
    database: "sqlite",
    sqlite_sync: "NORMAL"
  ),
}

all_scenarios = %w[login read_hot read_broad mixed_journey crud_cycle].to_h do |name|
  [name, Scenario.new(
    name: name,
    script: File.join(DATABASE_DIR, "wrk", "#{name}.lua"),
    dynamic_session: name == "mixed_journey"
  )]
end

variants = options[:variant_names].map { |name| all_variants.fetch(name) }
scenarios = options[:scenario_names].map { |name| all_scenarios.fetch(name) }
scenarios.each { |scenario| abort "Missing workload: #{scenario.script}" unless File.file?(scenario.script) }

inventory = JSON.parse(File.read(options[:inventory]))
target = inventory.fetch("resources").fetch("target")
loadgen = inventory.fetch("resources").fetch("loadgen")
known_hosts = "/tmp/#{inventory.fetch("prefix")}-database-runner-known-hosts"
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
  capture!("ssh", *ssh_options, "root@#{host}", command)
end

def scp_capture(source, destination, ssh_options)
  capture!("scp", *ssh_options, source, destination)
end

def seconds(value)
  match = value.to_s.strip.match(/\A([0-9.]+)(us|ms|s|m|h)\z/)
  raise "Unable to parse duration: #{value.inspect}" unless match

  number = match[1].to_f
  case match[2]
  when "us" then number / 1_000_000.0
  when "ms" then number / 1_000.0
  when "s" then number
  when "m" then number * 60.0
  when "h" then number * 3_600.0
  end
end

def parse_wrk(output)
  requests_per_second = output[/Requests\/sec:\s+([0-9.]+)/, 1]
  total_match = output.match(/([0-9]+) requests in ([0-9.]+(?:us|ms|s|m|h)),/)
  p50 = output[/^\s*50%\s+([0-9.]+(?:us|ms|s|m|h))\s*$/i, 1]
  p99 = output[/^\s*99%\s+([0-9.]+(?:us|ms|s|m|h))\s*$/i, 1]
  application_errors = output[/APPLICATION_ERRORS:\s+([0-9]+)/, 1]
  raise "Unable to parse wrk output:\n#{output}" unless requests_per_second && total_match && p50 && p99 && application_errors

  socket_errors = if line = output[/Socket errors:\s+connect ([0-9]+), read ([0-9]+), write ([0-9]+), timeout ([0-9]+)/, 0]
                    line.scan(/[0-9]+/).map(&:to_i).sum
                  else
                    0
                  end
  {
    "requests_per_second" => requests_per_second.to_f,
    "total_requests" => total_match[1].to_i,
    "elapsed_seconds" => seconds(total_match[2]),
    "p50_seconds" => seconds(p50),
    "p99_seconds" => seconds(p99),
    "socket_errors" => socket_errors,
    "non_2xx_responses" => (output[/Non-2xx or 3xx responses:\s+([0-9]+)/, 1] || "0").to_i,
    "application_errors" => application_errors.to_i,
  }
end

def parse_properties(output)
  output.lines.each_with_object({}) do |line, result|
    key, value = line.strip.split("=", 2)
    result[key] = value if key && value
  end
end

def numeric_property(properties, key)
  value = properties.fetch(key, "0")
  value.match?(/\A[0-9]+\z/) ? value.to_i : 0
end

def percentile(values, fraction)
  sorted = values.sort
  return 0.0 if sorted.empty?
  sorted[((sorted.size - 1) * fraction).round]
end

def summarize(values)
  return {"count" => 0} if values.empty?
  mean = values.sum / values.size.to_f
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

def unit_stats(host, ssh_options, unit)
  properties = %w[
    CPUUsageNSec MemoryCurrent MemoryPeak TasksCurrent
    IOReadBytes IOWriteBytes
  ].map { |name| "--property=#{name}" }.join(" ")
  parse_properties(ssh_capture(host, ssh_options, "systemctl show #{Shellwords.escape(unit)}.service --no-pager #{properties}"))
end

def proc_snapshot(host, ssh_options)
  output = ssh_capture(host, ssh_options, <<~'SHELL')
    root_source=$(findmnt -no SOURCE /)
    device=${root_source##*/}
    printf 'device=%s\n' "$device"
    awk '/^cpu / {printf "cpu=%s\n", substr($0, 5)}' /proc/stat
    awk -v d="$device" '$3 == d {printf "disk=%s %s %s %s %s %s %s %s %s %s %s\n", $4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14}' /proc/diskstats
    awk '/^(pgfault|pgmajfault|pswpin|pswpout) / {printf "%s=%s\n", $1, $2}' /proc/vmstat
    awk '/^(MemTotal|MemAvailable|SwapTotal|SwapFree):/ {printf "%s=%s\n", $1, $2 * 1024}' /proc/meminfo
  SHELL
  properties = parse_properties(output)
  properties["cpu"] = properties.fetch("cpu").split.map(&:to_i)
  properties["disk"] = properties.fetch("disk", "0 0 0 0 0 0 0 0 0 0 0").split.map(&:to_i)
  %w[pgfault pgmajfault pswpin pswpout MemTotal MemAvailable SwapTotal SwapFree].each do |key|
    properties[key] = properties.fetch(key, "0").to_i
  end
  properties
end

def proc_delta(before, after, elapsed)
  cpu_delta = after.fetch("cpu").zip(before.fetch("cpu")).map { |right, left| right - left }
  cpu_total = cpu_delta.sum.to_f
  idle = cpu_delta.fetch(3, 0) + cpu_delta.fetch(4, 0)
  iowait = cpu_delta.fetch(4, 0)
  disk_delta = after.fetch("disk").zip(before.fetch("disk")).map { |right, left| right - left }
  {
    "target_cpu_utilization" => cpu_total.zero? ? 0.0 : (cpu_total - idle) / cpu_total,
    "target_iowait_fraction" => cpu_total.zero? ? 0.0 : iowait / cpu_total,
    "disk_read_bytes" => disk_delta.fetch(2, 0) * 512,
    "disk_write_bytes" => disk_delta.fetch(6, 0) * 512,
    "disk_busy_seconds" => disk_delta.fetch(9, 0) / 1_000.0,
    "disk_utilization" => elapsed.zero? ? 0.0 : (disk_delta.fetch(9, 0) / 1_000.0) / elapsed,
    "page_faults" => after.fetch("pgfault") - before.fetch("pgfault"),
    "major_page_faults" => after.fetch("pgmajfault") - before.fetch("pgmajfault"),
    "swap_in_pages" => after.fetch("pswpin") - before.fetch("pswpin"),
    "swap_out_pages" => after.fetch("pswpout") - before.fetch("pswpout"),
    "memory_available_bytes" => after.fetch("MemAvailable"),
    "swap_total_bytes" => after.fetch("SwapTotal"),
  }
end

def pg_unit(target, ssh_options)
  ssh_capture(target.fetch("public_ip"), ssh_options, "pg_lsclusters --no-header | awk 'NR == 1 {print \"postgresql@\" $1 \"-\" $2}'").strip
end

def prepare_variant(target, ssh_options, variant, postgres_unit)
  host = target.fetch("public_ip")
  if variant.database == "postgresql"
    ssh_capture(host, ssh_options, "systemctl start #{Shellwords.escape(postgres_unit)}.service && pg_isready -h 127.0.0.1 -d amber_bench")
  else
    ssh_capture(host, ssh_options, "systemctl stop #{Shellwords.escape(postgres_unit)}.service")
  end
end

def prepare_cold_cache(target, ssh_options, variant, postgres_unit)
  host = target.fetch("public_ip")
  if variant.database == "postgresql"
    ssh_capture(host, ssh_options, "systemctl restart #{Shellwords.escape(postgres_unit)}.service && pg_isready -h 127.0.0.1 -d amber_bench")
  end
  ssh_capture(host, ssh_options, "sync; echo 3 > /proc/sys/vm/drop_caches")
end

def reset_mutable_data(target, ssh_options, variant)
  host = target.fetch("public_ip")
  seed_hash = "7b529f08962dc96604dc0a21320eaa5f971f3a4ee36369569246bd13e9ff8133"
  if variant.database == "postgresql"
    sql = "DELETE FROM benchmark_sessions WHERE token_hash <> '#{seed_hash}'; TRUNCATE benchmark_resource_events RESTART IDENTITY; CHECKPOINT;"
    command = "runuser -u postgres -- psql --dbname=amber_bench --set=ON_ERROR_STOP=1 --command=#{Shellwords.escape(sql)} >/dev/null"
  else
    sqlite = "/opt/amber-database/data/benchmark.sqlite3"
    sql = "PRAGMA busy_timeout=5000; DELETE FROM benchmark_sessions WHERE token_hash <> '#{seed_hash}'; DELETE FROM benchmark_resource_events; PRAGMA wal_checkpoint(TRUNCATE);"
    command = "sqlite3 #{Shellwords.escape(sqlite)} #{Shellwords.escape(sql)} >/dev/null"
  end
  ssh_capture(host, ssh_options, command)
end

def start_server(target, loadgen, ssh_options, variant, unit, options)
  database_url = if variant.database == "postgresql"
                   "postgres://amber_bench:amber-benchmark-local@127.0.0.1:5432/amber_bench?max_idle_pool_size=8"
                 else
                   "sqlite3:/opt/amber-database/data/benchmark.sqlite3?max_idle_pool_size=8"
                 end
  command = [
    "systemd-run", "--quiet", "--collect", "--unit=#{unit}",
    "--property=CPUAccounting=yes", "--property=MemoryAccounting=yes", "--property=IOAccounting=yes",
    "--setenv=DATABASE_URL=#{database_url}",
    "--setenv=SQLITE_SYNCHRONOUS=#{variant.sqlite_sync || "FULL"}",
    variant.binary,
    "--host=#{target.fetch("private_ip")}", "--port=#{options.fetch(:port)}", "--routes=#{options.fetch(:routes)}",
  ].map { |value| Shellwords.escape(value) }.join(" ")
  ssh_capture(target.fetch("public_ip"), ssh_options, command)

  expected = variant.database == "postgresql" ? "postgresql" : "sqlite"
  ready_url = "http://#{target.fetch("private_ip")}:#{options.fetch(:port)}/benchmark/health"
  readiness = "for i in $(seq 1 200); do body=$(curl -fsS --max-time 1 #{Shellwords.escape(ready_url)} 2>/dev/null || true); case \"$body\" in *\"\\\"database\\\":\\\"#{expected}\\\"\"*) exit 0;; esac; sleep 0.1; done; exit 1"
  ssh_capture(loadgen.fetch("public_ip"), ssh_options, readiness)
end

def stop_server(target, ssh_options, unit)
  ssh_capture(target.fetch("public_ip"), ssh_options, "systemctl stop #{Shellwords.escape(unit)}.service >/dev/null 2>&1 || true")
end

def run_wrk(loadgen, target, ssh_options, scenario, connections, duration, port, request_timeout, measured: true)
  threads = scenario.dynamic_session ? connections : [connections, 4].min
  url = "http://#{target.fetch("private_ip")}:#{port}"
  remote_script = "/opt/amber-database/workloads/#{File.basename(scenario.script)}"
  command = [
    "wrk", "--threads", threads.to_s, "--connections", connections.to_s,
    "--duration", duration, "--timeout", request_timeout, "--latency", "--script", remote_script, url,
  ].map { |value| Shellwords.escape(value) }.join(" ")
  output = ssh_capture(loadgen.fetch("public_ip"), ssh_options, command)
  measured ? [parse_wrk(output), output, threads] : nil
end

def safe_unit_name(variant, scenario, repetition, connections)
  "amber-db-#{variant.name}-#{scenario.name}-r#{repetition}-c#{connections}".gsub(/[^a-zA-Z0-9_.@-]/, "-")[0, 220]
end

def database_sizes(target, ssh_options, variant)
  host = target.fetch("public_ip")
  if variant.database == "postgresql"
    bytes = ssh_capture(host, ssh_options, "runuser -u postgres -- psql --dbname=amber_bench --tuples-only --no-align --command=\"SELECT pg_database_size('amber_bench')\"").to_i
    {"database_bytes" => bytes, "wal_bytes" => 0}
  else
    output = ssh_capture(host, ssh_options, "printf 'database_bytes='; stat -c %s /opt/amber-database/data/benchmark.sqlite3; printf 'wal_bytes='; stat -c %s /opt/amber-database/data/benchmark.sqlite3-wal 2>/dev/null || echo 0")
    values = parse_properties(output)
    {"database_bytes" => values.fetch("database_bytes").to_i, "wal_bytes" => values.fetch("wal_bytes").to_i}
  end
end

def write_payload(path, payload)
  FileUtils.mkdir_p(File.dirname(path))
  temporary = "#{path}.tmp"
  File.write(temporary, JSON.pretty_generate(payload))
  File.rename(temporary, path)
end

variants.each do |variant|
  ssh_capture(target.fetch("public_ip"), ssh_options, "test -x #{Shellwords.escape(variant.binary)}")
end
ssh_capture(loadgen.fetch("public_ip"), ssh_options, "command -v wrk")
ssh_capture(target.fetch("public_ip"), ssh_options, "test $(awk '/SwapTotal/ {print $2}' /proc/meminfo) -eq 0")

scenarios.each do |scenario|
  remote = "/opt/amber-database/workloads/#{File.basename(scenario.script)}"
  scp_capture(scenario.script, "root@#{loadgen.fetch("public_ip")}:#{remote}", ssh_options)
end

postgres_unit = pg_unit(target, ssh_options)
output_path = options[:output]
raw_dir = output_path.sub(/\.json\z/, "_raw")
FileUtils.mkdir_p(raw_dir)

hardware = {
  "target" => {
    "size" => target.fetch("size"),
    "cpu" => JSON.parse(ssh_capture(target.fetch("public_ip"), ssh_options, "lscpu -J")),
    "memory_bytes" => ssh_capture(target.fetch("public_ip"), ssh_options, "awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo").to_i,
    "swap_bytes" => ssh_capture(target.fetch("public_ip"), ssh_options, "awk '/SwapTotal/ {print $2 * 1024}' /proc/meminfo").to_i,
    "kernel" => ssh_capture(target.fetch("public_ip"), ssh_options, "uname -a").strip,
    "disk" => ssh_capture(target.fetch("public_ip"), ssh_options, "lsblk -J -b -o NAME,SIZE,TYPE,MOUNTPOINTS,ROTA,MODEL"),
    "postgres" => ssh_capture(target.fetch("public_ip"), ssh_options, "psql --version").strip,
    "sqlite" => ssh_capture(target.fetch("public_ip"), ssh_options, "sqlite3 --version").strip,
    "postgres_unit" => postgres_unit,
  },
  "loadgen" => {
    "size" => loadgen.fetch("size"),
    "cpu" => JSON.parse(ssh_capture(loadgen.fetch("public_ip"), ssh_options, "lscpu -J")),
    "kernel" => ssh_capture(loadgen.fetch("public_ip"), ssh_options, "uname -a").strip,
    "wrk" => ssh_capture(loadgen.fetch("public_ip"), ssh_options, "wrk -v 2>&1 || true").lines.first.to_s.strip,
  },
}

binary_metadata = variants.map do |variant|
  output = ssh_capture(target.fetch("public_ip"), ssh_options, "printf 'bytes='; stat -c %s #{Shellwords.escape(variant.binary)}; printf 'sha256='; sha256sum #{Shellwords.escape(variant.binary)} | awk '{print $1}'")
  values = parse_properties(output)
  {
    "variant" => variant.name,
    "binary" => File.basename(variant.binary),
    "bytes" => values.fetch("bytes").to_i,
    "sha256" => values.fetch("sha256"),
    "database" => variant.database,
    "sqlite_synchronous" => variant.sqlite_sync,
  }
end

fio_output = ssh_capture(target.fetch("public_ip"), ssh_options, <<~SHELL)
  fio --name=amber-r23-disk --filename=/opt/amber-database/data/fio-probe.bin --size=128m --direct=1 --ioengine=libaio --rw=randrw --rwmixread=70 --bs=4k --iodepth=16 --runtime=10 --time_based --group_reporting --output-format=json
SHELL
File.write(File.join(raw_dir, "fio.json"), fio_output)
ssh_capture(target.fetch("public_ip"), ssh_options, "rm -f /opt/amber-database/data/fio-probe.bin; sync; echo 3 > /proc/sys/vm/drop_caches")

payload = {
  "metadata" => {
    "generated_at_utc" => Time.now.utc.iso8601,
    "source_commit" => capture!("git", "-C", ROOT_DIR, "rev-parse", "HEAD").strip,
    "compiler_lane" => options[:compiler],
    "route_count" => options[:routes],
    "user_rows" => 10_000,
    "resource_rows" => 1_000_000,
    "bcrypt_cost" => 10,
    "session_behavior" => "bearer token SHA-256 plus indexed database session lookup on every authenticated request",
    "cache_mode" => options[:cold_cache] ? "cold start with database and OS caches reset before every trial" : "warm steady state",
    "warmup" => options[:cold_cache] ? "none" : options[:warmup],
    "duration" => options[:duration],
    "request_timeout" => options[:timeout],
    "repetitions" => options[:repetitions],
    "connections" => options[:connections],
    "variant_order" => variants.map(&:name),
    "scenario_order" => scenarios.map(&:name),
    "postgres_durability" => "fsync=on, full_page_writes=on, synchronous_commit=on",
    "sqlite_durability" => "WAL with separately labeled FULL and NORMAL synchronous lanes",
    "swap_policy" => "temporary setup swap disabled before all trials",
    "hardware" => hardware,
    "binaries" => binary_metadata,
    "fio_raw_result" => File.join(File.basename(raw_dir), "fio.json"),
  },
  "trials" => [],
  "aggregates" => {},
}

trial_sequence = 0
options[:repetitions].times do |repetition_index|
  repetition = repetition_index + 1
  scenarios.rotate(repetition_index % scenarios.size).each_with_index do |scenario, scenario_index|
    options[:connections].each do |connections|
      rotation = (repetition_index + scenario_index) % variants.size
      variants.rotate(rotation).each do |variant|
        trial_sequence += 1
        unit = safe_unit_name(variant, scenario, repetition, connections)
        begin
          prepare_variant(target, ssh_options, variant, postgres_unit)
          reset_mutable_data(target, ssh_options, variant)
          if options[:cold_cache]
            prepare_cold_cache(target, ssh_options, variant, postgres_unit)
            start_server(target, loadgen, ssh_options, variant, unit, options)
          else
            start_server(target, loadgen, ssh_options, variant, unit, options)
            run_wrk(loadgen, target, ssh_options, scenario, connections, options[:warmup], options[:port], options[:timeout], measured: false)
            reset_mutable_data(target, ssh_options, variant)
          end

          app_before = unit_stats(target.fetch("public_ip"), ssh_options, unit)
          pg_before = variant.database == "postgresql" ? unit_stats(target.fetch("public_ip"), ssh_options, postgres_unit) : {}
          proc_before = proc_snapshot(target.fetch("public_ip"), ssh_options)
          result, raw_output, threads = run_wrk(loadgen, target, ssh_options, scenario, connections, options[:duration], options[:port], options[:timeout])
          proc_after = proc_snapshot(target.fetch("public_ip"), ssh_options)
          app_after = unit_stats(target.fetch("public_ip"), ssh_options, unit)
          pg_after = variant.database == "postgresql" ? unit_stats(target.fetch("public_ip"), ssh_options, postgres_unit) : {}

          %w[socket_errors non_2xx_responses application_errors].each do |key|
            raise "#{unit} had #{result.fetch(key)} #{key}" unless result.fetch(key).zero?
          end
          raise "swap became active during #{unit}" unless proc_after.fetch("SwapTotal").zero?

          elapsed = result.fetch("elapsed_seconds")
          app_cpu = (numeric_property(app_after, "CPUUsageNSec") - numeric_property(app_before, "CPUUsageNSec")) / (elapsed * 1_000_000_000.0)
          pg_cpu = if variant.database == "postgresql"
                     (numeric_property(pg_after, "CPUUsageNSec") - numeric_property(pg_before, "CPUUsageNSec")) / (elapsed * 1_000_000_000.0)
                   else
                     0.0
                   end
          system_delta = proc_delta(proc_before, proc_after, elapsed)
          sizes = database_sizes(target, ssh_options, variant)
          raw_path = File.join(raw_dir, "#{unit}.txt")
          File.write(raw_path, raw_output)
          invocation_id = ssh_capture(
            target.fetch("public_ip"),
            ssh_options,
            "systemctl show #{Shellwords.escape(unit)}.service --property=InvocationID --value"
          ).strip
          raise "Missing systemd invocation ID for #{unit}" if invocation_id.empty?
          journal = ssh_capture(
            target.fetch("public_ip"),
            ssh_options,
            "journalctl --no-pager -n 30 _SYSTEMD_INVOCATION_ID=#{Shellwords.escape(invocation_id)}"
          )

          trial = result.merge(system_delta).merge(sizes).merge(
            "variant" => variant.name,
            "database" => variant.database,
            "sqlite_synchronous" => variant.sqlite_sync,
            "scenario" => scenario.name,
            "repetition" => repetition,
            "connections" => connections,
            "loadgen_threads" => threads,
            "trial_sequence" => trial_sequence,
            "amber_cpu_cores" => app_cpu,
            "database_cpu_cores" => pg_cpu,
            "combined_cpu_cores" => app_cpu + pg_cpu,
            "requests_per_combined_cpu_second" => result.fetch("requests_per_second") / (app_cpu + pg_cpu),
            "amber_memory_current_bytes" => numeric_property(app_after, "MemoryCurrent"),
            "amber_memory_peak_bytes" => numeric_property(app_after, "MemoryPeak"),
            "database_memory_current_bytes" => numeric_property(pg_after, "MemoryCurrent"),
            "database_memory_peak_bytes" => numeric_property(pg_after, "MemoryPeak"),
            "combined_memory_current_bytes" => numeric_property(app_after, "MemoryCurrent") + numeric_property(pg_after, "MemoryCurrent"),
            "amber_io_read_bytes" => numeric_property(app_after, "IOReadBytes") - numeric_property(app_before, "IOReadBytes"),
            "amber_io_write_bytes" => numeric_property(app_after, "IOWriteBytes") - numeric_property(app_before, "IOWriteBytes"),
            "raw_result" => File.join(File.basename(raw_dir), File.basename(raw_path)),
            "server_log" => journal.lines.map(&:strip).reject(&:empty?)
          )
          payload.fetch("trials") << trial
          write_payload(output_path, payload)
          warn format(
            "%s %-13s r%d c%d: %.0f RPS p50 %.1f ms p99 %.1f ms CPU %.1f%% mem %.1f MiB disk R/W %.1f/%.1f MiB",
            variant.name,
            scenario.name,
            repetition,
            connections,
            trial.fetch("requests_per_second"),
            trial.fetch("p50_seconds") * 1_000,
            trial.fetch("p99_seconds") * 1_000,
            trial.fetch("combined_cpu_cores") * 100,
            trial.fetch("combined_memory_current_bytes") / 1_048_576.0,
            trial.fetch("disk_read_bytes") / 1_048_576.0,
            trial.fetch("disk_write_bytes") / 1_048_576.0
          )
        ensure
          stop_server(target, ssh_options, unit)
        end
      end
    end
  end
end

aggregates = {}
scenarios.each do |scenario|
  aggregates[scenario.name] = {}
  options[:connections].each do |connections|
    key = connections.to_s
    aggregates[scenario.name][key] = {}
    postgres_median = nil
    variants.each do |variant|
      rows = payload.fetch("trials").select do |trial|
        trial.fetch("scenario") == scenario.name &&
          trial.fetch("connections") == connections &&
          trial.fetch("variant") == variant.name
      end
      rps = summarize(rows.map { |row| row.fetch("requests_per_second") })
      postgres_median = rps.fetch("median") if variant.name == "postgres"
      aggregates[scenario.name][key][variant.name] = {
        "requests_per_second" => rps,
        "p50_seconds" => summarize(rows.map { |row| row.fetch("p50_seconds") }),
        "p99_seconds" => summarize(rows.map { |row| row.fetch("p99_seconds") }),
        "combined_cpu_cores" => summarize(rows.map { |row| row.fetch("combined_cpu_cores") }),
        "requests_per_combined_cpu_second" => summarize(rows.map { |row| row.fetch("requests_per_combined_cpu_second") }),
        "combined_memory_current_bytes" => summarize(rows.map { |row| row.fetch("combined_memory_current_bytes") }),
        "disk_read_bytes" => summarize(rows.map { |row| row.fetch("disk_read_bytes") }),
        "disk_write_bytes" => summarize(rows.map { |row| row.fetch("disk_write_bytes") }),
        "major_page_faults" => summarize(rows.map { |row| row.fetch("major_page_faults") }),
        "pair_wins_vs_postgres" => if variant.name == "postgres"
                                      nil
                                    else
                                      rows.count do |row|
                                        paired = payload.fetch("trials").find do |candidate|
                                          candidate.fetch("scenario") == scenario.name &&
                                            candidate.fetch("connections") == connections &&
                                            candidate.fetch("repetition") == row.fetch("repetition") &&
                                            candidate.fetch("variant") == "postgres"
                                        end
                                        paired && row.fetch("requests_per_second") > paired.fetch("requests_per_second")
                                      end
                                    end,
        "median_rps_ratio_vs_postgres" => postgres_median && rps.fetch("median") / postgres_median,
      }
    end
  end
end

payload["aggregates"] = aggregates
payload["metadata"]["completed_at_utc"] = Time.now.utc.iso8601
write_payload(output_path, payload)
puts "Wrote #{output_path} with #{payload.fetch("trials").size} successful trials"
