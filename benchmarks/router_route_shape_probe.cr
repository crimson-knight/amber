require "json"
require "option_parser"
require "../src/amber/router/engine"
require "./router_revalidation_support"

module Amber::Benchmarks::RouterRouteShapeProbe
  extend self

  alias Router = Amber::Router::RouteSet(Int32)
  alias Measurement = NamedTuple(
    profile: String,
    strategy: String,
    repetition: Int32,
    operations: Int64,
    elapsed_seconds: Float64,
    ips: Float64,
    ns_per_operation: Float64,
    allocated_bytes: UInt64,
    bytes_per_operation: Float64,
    sink: Int32)
  alias Summary = NamedTuple(
    count: Int32,
    min: Float64,
    median: Float64,
    mean: Float64,
    max: Float64,
    stddev: Float64,
    coefficient_of_variation: Float64)
  alias Aggregate = NamedTuple(
    ips: Summary,
    ns_per_operation: Summary,
    bytes_per_operation: Summary)

  STRATEGIES = [:legacy, :optimized]

  def build_router(definitions : Array(RouterRevalidation::RouteDefinition)) : Router
    Router.new.tap do |router|
      definitions.each do |definition|
        router.add(definition.trail, definition.payload, definition.constraints)
      end
    end
  end

  private def consume(result : Amber::Router::RoutedResult(Int32)) : Int32
    sink = result.payload? || -1
    if value = result["id"]?
      sink &+= value.bytesize
    end
    if value = result["child_id"]?
      sink &+= value.bytesize
    end
    if value = result["path"]?
      sink &+= value.bytesize
    end
    sink
  end

  private def run_workload(
    router : Router,
    traffic : Array(RouterRevalidation::TrafficRequest),
    strategy : Symbol,
    operations : Int64,
  ) : Int32
    mask = traffic.size - 1
    index = 0_i64
    sink = 0
    while index < operations
      request = traffic[(index & mask).to_i]
      result = if strategy == :legacy
                 # Mirrors Router#find_route before the optimization, including
                 # method/path concatenation and split-path allocations.
                 router.find("get#{request.resource}")
               else
                 router.find_span("get", request.resource)
               end
      sink &+= consume(result)
      index += 1
    end
    sink
  end

  private def verify(
    router : Router,
    profile : Symbol,
    traffic : Array(RouterRevalidation::TrafficRequest),
  ) : Nil
    traffic.each do |request|
      legacy = router.find("get#{request.resource}")
      optimized = router.find_span("get", request.resource)
      unless legacy.found? == optimized.found? && legacy.payload? == optimized.payload? && legacy.params == optimized.params
        raise "strategy mismatch for #{profile}: #{request.resource}"
      end
    end
  end

  private def measure(
    router : Router,
    traffic : Array(RouterRevalidation::TrafficRequest),
    profile : Symbol,
    strategy : Symbol,
    repetition : Int32,
    operations : Int64,
    warmup_operations : Int64,
  ) : Measurement
    run_workload(router, traffic, strategy, warmup_operations)
    GC.collect
    before = GC.stats
    started_at = Time.instant
    sink = run_workload(router, traffic, strategy, operations)
    elapsed = (Time.instant - started_at).total_seconds
    allocated_bytes = GC.stats.total_bytes - before.total_bytes

    {
      profile:             profile.to_s,
      strategy:            strategy.to_s,
      repetition:          repetition,
      operations:          operations,
      elapsed_seconds:     elapsed,
      ips:                 operations / elapsed,
      ns_per_operation:    elapsed * 1_000_000_000 / operations,
      allocated_bytes:     allocated_bytes,
      bytes_per_operation: allocated_bytes.to_f64 / operations,
      sink:                sink,
    }
  end

  private def summarize(values : Array(Float64)) : Summary
    sorted = values.sort
    mean = values.sum / values.size
    variance = values.sum { |value| (value - mean)**2 } / values.size
    {
      count:                    values.size,
      min:                      values.min,
      median:                   sorted[(sorted.size - 1) // 2],
      mean:                     mean,
      max:                      values.max,
      stddev:                   Math.sqrt(variance),
      coefficient_of_variation: mean.zero? ? 0.0 : Math.sqrt(variance) / mean,
    }
  end

  def run(
    route_count : Int32,
    profiles : Array(Symbol),
    operations : Int64,
    warmup_operations : Int64,
    repetitions : Int32,
    output_path : String,
  ) : Nil
    definitions = RouterRevalidation.generate_routes(route_count)
    router = build_router(definitions)
    traffic_by_profile = profiles.to_h do |profile|
      traffic = RouterRevalidation.generate_profile_traffic(definitions, profile)
      verify(router, profile, traffic)
      {profile, traffic}
    end
    measurements = [] of Measurement

    repetitions.times do |repetition_index|
      repetition = repetition_index + 1
      profiles.rotate(repetition_index % profiles.size).each_with_index do |profile, profile_index|
        STRATEGIES.rotate((repetition_index + profile_index) % STRATEGIES.size).each do |strategy|
          measurement = measure(
            router,
            traffic_by_profile[profile],
            profile,
            strategy,
            repetition,
            operations,
            warmup_operations
          )
          measurements << measurement
          puts "#{profile.to_s.ljust(22)} | #{strategy.to_s.ljust(9)} | #{measurement[:ips].round.to_i} ops/s | #{measurement[:ns_per_operation].round(2)} ns/op | #{measurement[:bytes_per_operation].round(2)} B/op"
        end
      end
    end

    aggregates = Hash(String, Hash(String, Aggregate)).new
    profiles.each do |profile|
      profile_aggregates = Hash(String, Aggregate).new
      STRATEGIES.each do |strategy|
        rows = measurements.select { |row| row[:profile] == profile.to_s && row[:strategy] == strategy.to_s }
        profile_aggregates[strategy.to_s] = {
          ips:                 summarize(rows.map(&.[:ips])),
          ns_per_operation:    summarize(rows.map(&.[:ns_per_operation])),
          bytes_per_operation: summarize(rows.map(&.[:bytes_per_operation])),
        }
      end
      aggregates[profile.to_s] = profile_aggregates
    end

    payload = {
      metadata: {
        compiler:                  Crystal::DESCRIPTION,
        generated_at_utc:          Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
        route_count:               route_count,
        route_mix:                 "45% static; 25% REST ID; 15% dynamic action; 5% nested; 5% constrained; 5% glob",
        traffic_entries:           4096,
        profiles:                  profiles.map(&.to_s),
        profile_descriptions:      profiles.to_h { |profile| {profile.to_s, RouterRevalidation.profile_description(profile)} },
        operations:                operations,
        warmup_operations:         warmup_operations,
        repetitions:               repetitions,
        parameter_values_consumed: true,
        legacy_scope:              "method/path concatenation, split matcher, parameter materialization",
        optimized_scope:           "method-root selection, byte-span matcher, parameter materialization",
      },
      aggregates: aggregates,
      trials:     measurements,
    }

    File.write(output_path, payload.to_pretty_json)
    puts "Wrote #{output_path}"
  end
end

route_count = 1000
profiles = Amber::Benchmarks::RouterRevalidation::TRAFFIC_PROFILES
operations = 1_000_000_i64
warmup_operations = 100_000_i64
repetitions = 5
output_path = "benchmarks/results/router_route_shape_probe.json"

OptionParser.parse do |parser|
  parser.banner = "Usage: router_route_shape_probe [options]"
  parser.on("--routes=COUNT", "Number of mixed routes") { |value| route_count = value.to_i }
  parser.on("--profiles=LIST", "Comma-separated traffic profiles") do |value|
    profiles = value.split(',').map { |name| Amber::Benchmarks::RouterRevalidation.profile_from_string(name) }
  end
  parser.on("--operations=COUNT", "Measured operations per trial") { |value| operations = value.to_i64 }
  parser.on("--warmup=COUNT", "Warmup operations per trial") { |value| warmup_operations = value.to_i64 }
  parser.on("--repetitions=COUNT", "Rotated repetitions") { |value| repetitions = value.to_i }
  parser.on("--output=PATH", "JSON output path") { |value| output_path = value }
end

unknown_profiles = profiles - Amber::Benchmarks::RouterRevalidation::TRAFFIC_PROFILES
raise ArgumentError.new("unknown profiles: #{unknown_profiles.join(",")}") unless unknown_profiles.empty?

Amber::Benchmarks::RouterRouteShapeProbe.run(
  route_count,
  profiles,
  operations,
  warmup_operations,
  repetitions,
  output_path
)
