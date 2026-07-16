require "json"
require "option_parser"
require "../src/amber/router/engine"
require "./router_revalidation_support"

module Amber::Benchmarks::RouterRevalidationMicro
  extend self

  alias Router = Amber::Router::RouteSet(Int32)
  alias Measurement = NamedTuple(
    tier: Int32,
    strategy: String,
    workload: String,
    operations: Int64,
    elapsed_seconds: Float64,
    ips: Float64,
    ns_per_operation: Float64,
    allocated_bytes: UInt64,
    bytes_per_operation: Float64,
    sink: Int32)

  def build_router(definitions : Array(RouterRevalidation::RouteDefinition)) : Router
    Router.new.tap do |router|
      definitions.each do |definition|
        router.add(definition.trail, definition.payload, definition.constraints)
      end
    end
  end

  @[AlwaysInline]
  private def consume_result(result : Amber::Router::RoutedResult(Int32), request : RouterRevalidation::TrafficRequest, include_params : Bool) : Int32
    value = result.payload? || -1
    return value unless include_params && result.found?

    case request.kind
    when :variable, :constrained
      value &+= result["id"]?.try(&.bytesize) || 0
    when :nested
      value &+= result["id"]?.try(&.bytesize) || 0
      value &+= result["child_id"]?.try(&.bytesize) || 0
    when :glob
      value &+= result["path"]?.try(&.bytesize) || 0
    end

    value
  end

  private def run_current(router : Router, traffic : Array(RouterRevalidation::TrafficRequest), operations : Int64, include_params : Bool) : Int32
    mask = traffic.size - 1
    index = 0_i64
    sink = 0

    while index < operations
      request = traffic[(index & mask).to_i]
      sink &+= consume_result(router.find(request.path), request, include_params)
      index += 1
    end

    sink
  end

  private def measure(tier : Int32, strategy : String, workload : String, operations : Int64, warmup_operations : Int64, &run : Int64 -> Int32) : Measurement
    yield warmup_operations
    GC.collect
    before = GC.stats
    started_at = Time.instant
    sink = yield operations
    elapsed = (Time.instant - started_at).total_seconds
    allocated_bytes = GC.stats.total_bytes - before.total_bytes

    {
      tier:                tier,
      strategy:            strategy,
      workload:            workload,
      operations:          operations,
      elapsed_seconds:     elapsed,
      ips:                 operations / elapsed,
      ns_per_operation:    elapsed * 1_000_000_000 / operations,
      allocated_bytes:     allocated_bytes,
      bytes_per_operation: allocated_bytes.to_f64 / operations,
      sink:                sink,
    }
  end

  def run(tiers : Array(Int32), operations : Int64, warmup_operations : Int64, output_path : String) : Nil
    measurements = [] of Measurement

    tiers.each do |tier|
      definitions = RouterRevalidation.generate_routes(tier)
      traffic = RouterRevalidation.generate_traffic(definitions)
      router = build_router(definitions)

      {false, true}.each do |include_params|
        workload = include_params ? "mixed_dispatch_with_params" : "mixed_dispatch"
        measurement = measure(tier, "current_find", workload, operations, warmup_operations) do |count|
          run_current(router, traffic, count, include_params)
        end
        measurements << measurement

        puts "#{tier.to_s.rjust(4)} routes | #{workload.ljust(26)} | #{measurement[:ips].round.to_i} ops/s | #{measurement[:ns_per_operation].round(2)} ns/op | #{measurement[:bytes_per_operation].round(2)} B/op"
      end
    end

    payload = {
      metadata: {
        compiler:          Crystal::DESCRIPTION,
        generated_at_utc:  Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
        tiers:             tiers,
        operations:        operations,
        warmup_operations: warmup_operations,
        traffic_entries:   4096,
        traffic_mix:       "45% static, 40% variable, 5% nested, 5% constrained, 3% glob, 2% not-found; 70% hot-set",
      },
      results: measurements,
    }

    File.write(output_path, payload.to_pretty_json)
    puts "Wrote #{output_path}"
  end
end

tiers = [500, 1000, 1500]
operations = 5_000_000_i64
warmup_operations = 500_000_i64
output_path = "benchmarks/results/router_revalidation_micro.json"

OptionParser.parse do |parser|
  parser.banner = "Usage: router_revalidation_micro [options]"
  parser.on("--tiers=LIST", "Comma-separated route counts") { |value| tiers = value.split(',').map(&.to_i) }
  parser.on("--operations=COUNT", "Measured operations per workload") { |value| operations = value.to_i64 }
  parser.on("--warmup=COUNT", "Warmup operations per workload") { |value| warmup_operations = value.to_i64 }
  parser.on("--output=PATH", "JSON output path") { |value| output_path = value }
end

Amber::Benchmarks::RouterRevalidationMicro.run(tiers, operations, warmup_operations, output_path)
