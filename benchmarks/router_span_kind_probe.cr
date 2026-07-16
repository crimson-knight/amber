require "json"
require "option_parser"
require "../src/amber/router/engine"
require "./router_revalidation_support"

module Amber::Benchmarks::RouterSpanKindProbe
  extend self

  alias Router = Amber::Router::RouteSet(Int32)
  alias Measurement = NamedTuple(
    kind: String,
    operations: Int64,
    elapsed_seconds: Float64,
    ips: Float64,
    ns_per_operation: Float64,
    allocated_bytes: UInt64,
    bytes_per_operation: Float64,
    sink: Int32)

  KINDS = [:static, :variable, :nested, :constrained, :glob, :notfound]

  def build_router(definitions : Array(RouterRevalidation::RouteDefinition)) : Router
    Router.new.tap do |router|
      definitions.each do |definition|
        router.add(definition.trail, definition.payload, definition.constraints)
      end
    end
  end

  def build_traffic(definitions : Array(RouterRevalidation::RouteDefinition), kind : Symbol, size = 4096) : Array(RouterRevalidation::TrafficRequest)
    if kind == :notfound
      return Array.new(size) do |index|
        RouterRevalidation::TrafficRequest.new("get/api/v9/missing_#{index % 31}/#{index}", kind)
      end
    end

    matching = definitions.select { |definition| definition.kind == kind }
    Array.new(size) do |index|
      definition = matching[index % matching.size]
      RouterRevalidation::TrafficRequest.new("get#{definition.matching_resource(index)}", kind)
    end
  end

  private def run_workload(router : Router, traffic : Array(RouterRevalidation::TrafficRequest), operations : Int64) : Int32
    mask = traffic.size - 1
    index = 0_i64
    sink = 0
    while index < operations
      request = traffic[(index & mask).to_i]
      sink &+= router.find_span("get", request.resource).payload? || -1
      index += 1
    end
    sink
  end

  private def measure(kind : Symbol, operations : Int64, warmup_operations : Int64, &run : Int64 -> Int32) : Measurement
    yield warmup_operations
    GC.collect
    before = GC.stats
    started_at = Time.instant
    sink = yield operations
    elapsed = (Time.instant - started_at).total_seconds
    allocated_bytes = GC.stats.total_bytes - before.total_bytes

    {
      kind:                kind.to_s,
      operations:          operations,
      elapsed_seconds:     elapsed,
      ips:                 operations / elapsed,
      ns_per_operation:    elapsed * 1_000_000_000 / operations,
      allocated_bytes:     allocated_bytes,
      bytes_per_operation: allocated_bytes.to_f64 / operations,
      sink:                sink,
    }
  end

  def run(route_count : Int32, operations : Int64, warmup_operations : Int64, output_path : String) : Nil
    definitions = RouterRevalidation.generate_routes(route_count)
    router = build_router(definitions)
    measurements = [] of Measurement

    KINDS.each do |kind|
      traffic = build_traffic(definitions, kind)
      measurement = measure(kind, operations, warmup_operations) do |count|
        run_workload(router, traffic, count)
      end
      measurements << measurement
      puts "#{kind.to_s.ljust(12)} | #{measurement[:ips].round.to_i} ops/s | #{measurement[:ns_per_operation].round(2)} ns/op | #{measurement[:bytes_per_operation].round(2)} B/op"
    end

    payload = {
      metadata: {
        compiler:          Crystal::DESCRIPTION,
        generated_at_utc:  Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
        strategy:          "span_match",
        route_count:       route_count,
        traffic_entries:   4096,
        operations:        operations,
        warmup_operations: warmup_operations,
      },
      results: measurements,
    }

    File.write(output_path, payload.to_pretty_json)
    puts "Wrote #{output_path}"
  end
end

route_count = 1000
operations = 5_000_000_i64
warmup_operations = 500_000_i64
output_path = "benchmarks/results/router_span_kind_probe.json"

OptionParser.parse do |parser|
  parser.banner = "Usage: router_span_kind_probe [options]"
  parser.on("--routes=COUNT", "Number of mixed routes") { |value| route_count = value.to_i }
  parser.on("--operations=COUNT", "Measured operations per route kind") { |value| operations = value.to_i64 }
  parser.on("--warmup=COUNT", "Warmup operations per route kind") { |value| warmup_operations = value.to_i64 }
  parser.on("--output=PATH", "JSON output path") { |value| output_path = value }
end

Amber::Benchmarks::RouterSpanKindProbe.run(route_count, operations, warmup_operations, output_path)
