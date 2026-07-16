require "json"
require "option_parser"
require "../src/amber/router/engine"
require "./router_revalidation_support"

module Amber::Benchmarks::RouterExactDispatchProbe
  extend self

  alias Router = Amber::Router::RouteSet(Int32)
  alias Terminal = Amber::Router::TerminalSegment(Int32)
  alias Result = Amber::Router::RoutedResult(Int32)
  alias Measurement = NamedTuple(
    strategy: String,
    operations: Int64,
    elapsed_seconds: Float64,
    ips: Float64,
    ns_per_operation: Float64,
    allocated_bytes: UInt64,
    bytes_per_operation: Float64,
    sink: Int32)

  record Fixture,
    router : Router,
    method_router : Router,
    exact_terminals : Hash(String, Terminal),
    exact_terminal_array : Array(Terminal),
    shared_results : Hash(String, Result),
    traffic : Array(RouterRevalidation::TrafficRequest)

  def build_fixture(route_count : Int32, traffic_size = 4096) : Fixture
    definitions = RouterRevalidation.generate_routes(route_count)
    router = Router.new
    method_router = Router.new
    exact_terminals = {} of String => Terminal
    exact_terminal_array = [] of Terminal
    shared_results = {} of String => Result

    definitions.each_with_index do |definition, priority|
      router.add(definition.trail, definition.payload, definition.constraints)
      method_router.add(definition.resource, definition.payload, definition.constraints)
      next unless definition.kind == :static

      terminal = Terminal.new(definition.payload, definition.trail, priority)
      exact_terminals[definition.trail] = terminal
      exact_terminal_array << terminal
      shared_results[definition.trail] = Result.new(terminal)
    end

    static_definitions = definitions.select { |definition| definition.kind == :static }
    traffic = Array(RouterRevalidation::TrafficRequest).new(traffic_size)
    traffic_size.times do |index|
      definition = static_definitions[index % static_definitions.size]
      traffic << RouterRevalidation::TrafficRequest.new(definition.trail, :static)
    end

    Fixture.new(router, method_router, exact_terminals, exact_terminal_array, shared_results, traffic)
  end

  private def run_method_span(fixture : Fixture, operations : Int64) : Int32
    mask = fixture.traffic.size - 1
    index = 0_i64
    sink = 0
    while index < operations
      request = fixture.traffic[(index & mask).to_i]
      sink &+= fixture.method_router.find_span(request.resource).payload? || -1
      index += 1
    end
    sink
  end

  private def run_span(fixture : Fixture, operations : Int64) : Int32
    mask = fixture.traffic.size - 1
    index = 0_i64
    sink = 0
    while index < operations
      request = fixture.traffic[(index & mask).to_i]
      sink &+= fixture.router.find_span("get", request.resource).payload? || -1
      index += 1
    end
    sink
  end

  private def run_exact_result(fixture : Fixture, operations : Int64) : Int32
    mask = fixture.traffic.size - 1
    index = 0_i64
    sink = 0
    while index < operations
      request = fixture.traffic[(index & mask).to_i]
      sink &+= Result.new(fixture.exact_terminals[request.path]).payload? || -1
      index += 1
    end
    sink
  end

  private macro generated_static_route_id_for(path)
    {% actions = ["index", "new", "search", "stats", "export", "archive"] %}
    case {{ path }}
      {% for index in 0...675 %}
        {% action_index = index // 100 %}
        {% generation = action_index // actions.size %}
        {% suffix = generation == 0 ? "" : "/generation_#{generation}" %}
        when {{ "/api/v#{index % 3 + 1}/resource_#{index % 100}/#{actions[action_index % actions.size].id}#{suffix.id}" }}
          {{ index }}
      {% end %}
      else
        nil
    end
  end

  private def generated_static_route_id(path : String) : Int32?
    generated_static_route_id_for(path)
  end

  private def run_generated_result(fixture : Fixture, operations : Int64) : Int32
    mask = fixture.traffic.size - 1
    index = 0_i64
    sink = 0
    while index < operations
      request = fixture.traffic[(index & mask).to_i]
      route_id = generated_static_route_id(request.resource).not_nil!
      sink &+= Result.new(fixture.exact_terminal_array[route_id]).payload? || -1
      index += 1
    end
    sink
  end

  private def run_generated_payload(fixture : Fixture, operations : Int64) : Int32
    mask = fixture.traffic.size - 1
    index = 0_i64
    sink = 0
    while index < operations
      request = fixture.traffic[(index & mask).to_i]
      sink &+= generated_static_route_id(request.resource).not_nil!
      index += 1
    end
    sink
  end

  private def run_shared_result(fixture : Fixture, operations : Int64) : Int32
    mask = fixture.traffic.size - 1
    index = 0_i64
    sink = 0
    while index < operations
      request = fixture.traffic[(index & mask).to_i]
      sink &+= fixture.shared_results[request.path].payload? || -1
      index += 1
    end
    sink
  end

  private def run_exact_payload(fixture : Fixture, operations : Int64) : Int32
    mask = fixture.traffic.size - 1
    index = 0_i64
    sink = 0
    while index < operations
      request = fixture.traffic[(index & mask).to_i]
      sink &+= fixture.exact_terminals[request.path].route
      index += 1
    end
    sink
  end

  private def measure(strategy : String, operations : Int64, warmup_operations : Int64, &run : Int64 -> Int32) : Measurement
    yield warmup_operations
    GC.collect
    before = GC.stats
    started_at = Time.instant
    sink = yield operations
    elapsed = (Time.instant - started_at).total_seconds
    allocated_bytes = GC.stats.total_bytes - before.total_bytes

    {
      strategy:            strategy,
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
    fixture = build_fixture(route_count)
    measurements = [] of Measurement

    {
      "span_root_result"  => ->(count : Int64) { run_span(fixture, count) },
      "method_span"       => ->(count : Int64) { run_method_span(fixture, count) },
      "generated_result"  => ->(count : Int64) { run_generated_result(fixture, count) },
      "generated_payload" => ->(count : Int64) { run_generated_payload(fixture, count) },
      "exact_result"      => ->(count : Int64) { run_exact_result(fixture, count) },
      "shared_result"     => ->(count : Int64) { run_shared_result(fixture, count) },
      "exact_payload"     => ->(count : Int64) { run_exact_payload(fixture, count) },
    }.each do |strategy, runner|
      measurement = measure(strategy, operations, warmup_operations) { |count| runner.call(count) }
      measurements << measurement
      puts "#{strategy.ljust(18)} | #{measurement[:ips].round.to_i} ops/s | #{measurement[:ns_per_operation].round(2)} ns/op | #{measurement[:bytes_per_operation].round(2)} B/op"
    end

    sinks = measurements.map(&.[:sink]).uniq
    raise "strategy checksum mismatch: #{sinks}" unless sinks.size == 1

    payload = {
      metadata: {
        compiler:          Crystal::DESCRIPTION,
        generated_at_utc:  Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
        route_count:       route_count,
        static_routes:     fixture.exact_terminals.size,
        traffic_entries:   fixture.traffic.size,
        operations:        operations,
        warmup_operations: warmup_operations,
        scope:             "static-route code-generation ceiling; shared_result is intentionally not production-safe",
      },
      results: measurements,
    }

    File.write(output_path, payload.to_pretty_json)
    puts "Wrote #{output_path}"
  end
end

route_count = 1000
operations = 10_000_000_i64
warmup_operations = 1_000_000_i64
output_path = "benchmarks/results/router_exact_dispatch_probe.json"

OptionParser.parse do |parser|
  parser.banner = "Usage: router_exact_dispatch_probe [options]"
  parser.on("--routes=COUNT", "Number of mixed routes") { |value| route_count = value.to_i }
  parser.on("--operations=COUNT", "Measured operations per strategy") { |value| operations = value.to_i64 }
  parser.on("--warmup=COUNT", "Warmup operations per strategy") { |value| warmup_operations = value.to_i64 }
  parser.on("--output=PATH", "JSON output path") { |value| output_path = value }
end

Amber::Benchmarks::RouterExactDispatchProbe.run(route_count, operations, warmup_operations, output_path)
