require "benchmark"
require "json"
require "option_parser"
require "../src/amber/router/engine"

record StrategyConfig, key : String, label : String

TIERS      = [100, 1000, 5000, 10000]
STRATEGIES = [
  StrategyConfig.new("current_find", "Current find"),
  StrategyConfig.new("experimental_best", "Experimental best"),
]

def generate_routes(count : Int32) : Array({String, Symbol})
  routes = [] of {String, Symbol}
  resources = ["users", "posts", "comments", "tags", "categories",
               "products", "orders", "invoices", "settings", "teams",
               "projects", "tasks", "notifications", "messages", "files",
               "accounts", "roles", "permissions", "sessions", "tokens",
               "webhooks", "events", "logs", "audits", "reports",
               "dashboards", "widgets", "charts", "exports", "imports"]

  actions = ["index", "new", "create", "search", "export",
             "list", "show", "stats", "archive", "restore"]

  num_fixed = (count * 0.6).to_i
  base_combos = resources.size * actions.size
  num_fixed.times do |i|
    resource = resources[i % resources.size]
    action = actions[(i // resources.size) % actions.size]
    group = i // base_combos
    if group == 0
      routes << {"/#{resource}/#{action}", :"fixed_#{i}"}
    elsif group <= 3
      routes << {"/api/v#{group}/#{resource}/#{action}", :"fixed_#{i}"}
    else
      routes << {"/api/v#{((group - 1) % 3) + 1}/g#{group}/#{resource}/#{action}", :"fixed_#{i}"}
    end
  end

  num_variable = (count * 0.25).to_i
  num_variable.times do |i|
    resource = resources[i % resources.size]
    suffix = i // resources.size
    if suffix == 0
      routes << {"/#{resource}/:id", :"variable_#{i}"}
    else
      routes << {"/#{resource}/:id/detail#{suffix}", :"variable_#{i}"}
    end
  end

  num_constrained = (count * 0.1).to_i
  num_constrained.times do |i|
    resource = resources[i % resources.size]
    suffix = i // resources.size
    if suffix == 0
      routes << {"/#{resource}/:id/edit", :"constrained_#{i}"}
    else
      routes << {"/#{resource}/:id/edit#{suffix}", :"constrained_#{i}"}
    end
  end

  num_glob = (count * 0.05).to_i
  num_glob.times do |i|
    routes << {"/assets/v#{(i % 5) + 1}/*path#{i}", :"glob_#{i}"}
  end

  routes
end

def build_router(routes : Array({String, Symbol})) : Amber::Router::RouteSet(Symbol)
  router = Amber::Router::RouteSet(Symbol).new
  routes.each do |path, payload|
    router.add(path, payload)
  end
  router
end

def lookup(router : Amber::Router::RouteSet(Symbol), strategy_key : String, path : String) : Amber::Router::RoutedResult(Symbol)
  case strategy_key
  when "current_find"
    router.find(path)
  when "experimental_best"
    router.find_experimental_best(path)
  else
    raise "Unknown strategy: #{strategy_key}"
  end
end

def summarize_ratio(results : Array(Hash(String, Float64 | String | Int32)), metric_key : String, base_key : String, candidate_key : String)
  grouped = results.group_by { |row| {row["tier"], row["lookup_type"]} }
  ratios = [] of Float64

  grouped.each_value do |rows|
    base = rows.find { |row| row["strategy"] == base_key }
    candidate = rows.find { |row| row["strategy"] == candidate_key }
    next unless base && candidate

    base_value = base[metric_key].as(Float64)
    candidate_value = candidate[metric_key].as(Float64)
    next if base_value <= 0

    ratios << candidate_value / base_value
  end

  return nil if ratios.empty?

  {
    "mean_ratio"      => ratios.sum / ratios.size,
    "geometric_ratio" => Math.exp(ratios.sum { |ratio| Math.log(ratio) } / ratios.size),
  }
end

tiers = TIERS.dup
warmup_seconds = 2.0
calculation_seconds = 5.0
output_path = "benchmarks/results/strategy_compare_latest.json"
compiler_label = ENV["AMBER_BENCH_COMPILER"]? || "unknown"

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal run benchmarks/router_strategy_compare.cr -- [options]"

  parser.on("--tiers=LIST", "Comma-separated route-count tiers (default: #{TIERS.join(",")})") do |value|
    tiers = value.split(',').map(&.to_i)
  end

  parser.on("--warmup=SECONDS", "Warmup seconds per measurement (default: #{warmup_seconds})") do |value|
    warmup_seconds = value.to_f
  end

  parser.on("--calc=SECONDS", "Calculation seconds per measurement (default: #{calculation_seconds})") do |value|
    calculation_seconds = value.to_f
  end

  parser.on("--output=PATH", "Where to write the JSON results") do |value|
    output_path = value
  end
end

results = [] of Hash(String, Float64 | String | Int32)

puts "Amber Router Strategy Comparison"
puts "Crystal #{Crystal::VERSION}"
puts "Compiler: #{compiler_label}"
puts "Strategies: #{STRATEGIES.map(&.key).join(", ")}"
puts "Tiers: #{tiers.join(", ")}"

tiers.each do |tier|
  routes = generate_routes(tier)

  reg_time = Benchmark.realtime do
    build_router(routes)
  end

  router = build_router(routes)

  lookup_paths = {
    "fixed"    => "/users/index",
    "variable" => "/users/42",
    "glob"     => "/assets/v1/some/deep/nested/path",
    "notfound" => "/definitely/not/a/real/99999/route",
  }

  baseline_samples = lookup_paths.transform_values do |path|
    result = router.find(path)
    {
      "found"   => result.found?,
      "payload" => result.payload?.to_s,
      "params"  => result.params.to_h,
    }
  end

  STRATEGIES.each do |strategy|
    lookup_paths.each do |lookup_type, path|
      sample = lookup(router, strategy.key, path)
      expected = baseline_samples[lookup_type]

      if sample.found? != expected["found"] || sample.payload?.to_s != expected["payload"] || sample.params.to_h != expected["params"]
        raise "#{strategy.key} diverged for #{lookup_type} at tier #{tier}: expected #{expected}, got {found: #{sample.found?}, payload: #{sample.payload?.to_s}, params: #{sample.params.to_h}}"
      end

      memory = Benchmark.memory { lookup(router, strategy.key, path) }
      job = Benchmark.ips(warmup: warmup_seconds.seconds, calculation: calculation_seconds.seconds) do |x|
        x.report("#{strategy.key} #{lookup_type} #{tier}r") { lookup(router, strategy.key, path) }
      end
      ips = job.items.first.mean

      puts "#{tier.to_s.rjust(5)} routes | #{strategy.key.ljust(18)} | #{lookup_type.ljust(8)} | #{ips.round(0).to_s.rjust(9)} IPS | #{memory} B"

      results << {
        "tier"            => tier,
        "strategy"        => strategy.key,
        "strategy_label"  => strategy.label,
        "lookup_type"     => lookup_type,
        "registration_ms" => reg_time.total_milliseconds,
        "ips"             => ips,
        "memory_bytes"    => memory.to_f64,
      }
    end
  end
end

summary = {
  "ips"    => summarize_ratio(results, "ips", "current_find", "experimental_best"),
  "memory" => summarize_ratio(results, "memory_bytes", "current_find", "experimental_best"),
}

payload = {
  "metadata" => {
    "compiler"            => compiler_label,
    "crystal_version"     => Crystal::VERSION,
    "generated_at_utc"    => Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
    "tiers"               => tiers,
    "warmup_seconds"      => warmup_seconds,
    "calculation_seconds" => calculation_seconds,
    "strategies"          => STRATEGIES.map(&.key),
  },
  "summary" => summary,
  "results" => results,
}

timestamped_output = output_path.sub(/\.json$/, "_#{Time.local.to_s("%Y%m%d_%H%M%S")}.json")
File.write(output_path, payload.to_pretty_json)
File.write(timestamped_output, payload.to_pretty_json)

puts
puts "Wrote #{output_path}"
puts "Wrote #{timestamped_output}"
if ips_summary = summary["ips"]
  puts "Experimental IPS mean ratio: #{ips_summary["mean_ratio"]}"
  puts "Experimental IPS geometric ratio: #{ips_summary["geometric_ratio"]}"
end
