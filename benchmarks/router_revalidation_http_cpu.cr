require "json"
require "option_parser"
require "../src/amber"
require "./router_revalidation_support"

module Amber::Benchmarks::RouterRevalidationHTTPCPU
  extend self

  CONTENT_JSON           = "application/json; charset=utf-8"
  STATIC_BODY            = %({"status":"ok","framework":"amber","route":"static"})
  OPTIONAL_PARAM_LOOKUPS = {% if flag?(:amber_bench_optional_params) %}
                             true
                           {% else %}
                             false
                           {% end %}

  alias Measurement = NamedTuple(
    repetition: Int32,
    operations: Int32,
    elapsed_seconds: Float64,
    requests_per_second: Float64,
    ns_per_request: Float64,
    allocated_bytes: UInt64,
    bytes_per_request: Float64,
    response_bytes: UInt64,
    response_bytes_per_request: Float64)

  class CountingIO < IO
    getter bytes_written = 0_u64

    def read(slice : Bytes) : Int32
      0
    end

    def write(slice : Bytes) : Nil
      @bytes_written &+= slice.size.to_u64
    end
  end

  class Controller < Amber::Controller::Base
    def static_response
      exercise_optional_params
      set_response(STATIC_BODY, 200, CONTENT_JSON)
    end

    def dynamic_response
      exercise_optional_params
      id = params["id"]? || "missing"
      body = String.build(96) do |io|
        io << %({"status":"ok","framework":"amber","id":)
        id.to_json(io)
        io << '}'
      end
      set_response(body, 200, CONTENT_JSON)
    end

    def nested_response
      exercise_optional_params
      id = params["id"]? || "missing"
      child_id = params["child_id"]? || "missing"
      body = String.build(112) do |io|
        io << %({"status":"ok","framework":"amber","id":)
        id.to_json(io)
        io << %(,"child_id":)
        child_id.to_json(io)
        io << '}'
      end
      set_response(body, 200, CONTENT_JSON)
    end

    def glob_response
      exercise_optional_params
      path = params["path"]? || "missing"
      body = String.build(128) do |io|
        io << %({"status":"ok","framework":"amber","path":)
        path.to_json(io)
        io << '}'
      end
      set_response(body, 200, CONTENT_JSON)
    end

    private def exercise_optional_params : Nil
      {% if flag?(:amber_bench_optional_params) %}
        params["include"]?
        params["missing_optional"]?
      {% end %}
    end
  end

  def handler_for(kind : Symbol) : HTTP::Server::Context ->
    case kind
    when :static
      ->(context : HTTP::Server::Context) { Controller.new(context).static_response }
    when :nested
      ->(context : HTTP::Server::Context) { Controller.new(context).nested_response }
    when :glob
      ->(context : HTTP::Server::Context) { Controller.new(context).glob_response }
    else
      ->(context : HTTP::Server::Context) { Controller.new(context).dynamic_response }
    end
  end

  def install_routes(count : Int32) : Array(RouterRevalidation::RouteDefinition)
    RouterRevalidation.generate_routes(count).tap do |definitions|
      definitions.each do |definition|
        Amber::Server.router.add(
          Amber::Route.new(
            "GET",
            definition.resource,
            handler_for(definition.kind),
            :show,
            :web,
            Amber::Router::Scope.new,
            "Amber::Benchmarks::RouterRevalidationHTTPCPU::Controller",
            definition.constraints
          )
        )
      end
    end
  end

  def build_request_stream(traffic : Array(RouterRevalidation::TrafficRequest), operations : Int32) : String
    String.build(operations * 160) do |io|
      operations.times do |index|
        request = traffic[index % traffic.size]
        io << "GET " << request.resource
        io << "?include=profile&page=#{index % 11}" if index % 5 == 0
        io << " HTTP/1.1\r\n"
        io << "Host: amber.local\r\n"
        io << "Accept: application/json\r\n"
        io << "User-Agent: amber-framework-benchmark\r\n\r\n"
      end
    end
  end

  def process_stream(pipeline : Amber::Pipe::Pipeline, raw_requests : String) : CountingIO
    input = IO::Memory.new(raw_requests)
    output = CountingIO.new
    HTTP::Server::RequestProcessor.new(pipeline).process(input, output)
    output
  end

  def verify(pipeline : Amber::Pipe::Pipeline, traffic : Array(RouterRevalidation::TrafficRequest)) : Nil
    raw_requests = build_request_stream(traffic, 100)
    input = IO::Memory.new(raw_requests)
    output = IO::Memory.new
    HTTP::Server::RequestProcessor.new(pipeline).process(input, output)
    responses = output.to_s

    count = responses.scan(/HTTP\/1\.1 200 OK/).size
    raise "expected 100 successful responses, got #{count}" unless count == 100
  end

  def measure(pipeline : Amber::Pipe::Pipeline, raw_requests : String, operations : Int32, repetition : Int32) : Measurement
    GC.collect
    before = GC.stats
    started_at = Time.instant
    output = process_stream(pipeline, raw_requests)
    elapsed = (Time.instant - started_at).total_seconds
    allocated_bytes = GC.stats.total_bytes - before.total_bytes

    {
      repetition:                 repetition,
      operations:                 operations,
      elapsed_seconds:            elapsed,
      requests_per_second:        operations / elapsed,
      ns_per_request:             elapsed * 1_000_000_000 / operations,
      allocated_bytes:            allocated_bytes,
      bytes_per_request:          allocated_bytes.to_f64 / operations,
      response_bytes:             output.bytes_written,
      response_bytes_per_request: output.bytes_written.to_f64 / operations,
    }
  end

  def run(route_count : Int32, operations : Int32, warmup_operations : Int32, repetitions : Int32, output_path : String) : Nil
    definitions = install_routes(route_count)
    traffic = RouterRevalidation.generate_traffic(definitions, include_misses: false)
    pipeline = Amber::Pipe::Pipeline.new
    pipeline.prepare_pipelines
    verify(pipeline, traffic)

    warmup = build_request_stream(traffic, warmup_operations)
    process_stream(pipeline, warmup)
    raw_requests = build_request_stream(traffic, operations)

    measurements = Array(Measurement).new(repetitions)
    repetitions.times do |index|
      measurement = measure(pipeline, raw_requests, operations, index + 1)
      measurements << measurement
      puts "r#{index + 1} | #{measurement[:requests_per_second].round.to_i} req/s | #{measurement[:ns_per_request].round(2)} ns/request | #{measurement[:bytes_per_request].round(2)} B/request"
    end

    sorted_rps = measurements.map(&.[:requests_per_second]).sort
    sorted_bytes = measurements.map(&.[:bytes_per_request]).sort
    middle = repetitions // 2
    payload = {
      metadata: {
        compiler:               Crystal::DESCRIPTION,
        generated_at_utc:       Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
        route_count:            route_count,
        traffic_entries:        traffic.size,
        operations:             operations,
        warmup_operations:      warmup_operations,
        repetitions:            repetitions,
        traffic_mix:            "45% static, 40% variable, 5% nested, 5% constrained, 3% glob; 70% hot-set; 20% query strings",
        request_headers:        ["Host", "Accept", "User-Agent"],
        optional_param_lookups: OPTIONAL_PARAM_LOOKUPS,
        scope:                  "real Crystal HTTP parser and serializer plus full Amber pipeline; excludes sockets and kernel scheduling",
      },
      summary: {
        median_requests_per_second: sorted_rps[middle],
        median_bytes_per_request:   sorted_bytes[middle],
      },
      results: measurements,
    }

    File.write(output_path, payload.to_pretty_json)
    puts "Wrote #{output_path}"
  end
end

route_count = 1000
operations = 100_000
warmup_operations = 10_000
repetitions = 5
output_path = "benchmarks/results/router_revalidation_http_cpu.json"

OptionParser.parse do |parser|
  parser.banner = "Usage: router_revalidation_http_cpu [options]"
  parser.on("--routes=COUNT", "Number of mixed routes") { |value| route_count = value.to_i }
  parser.on("--operations=COUNT", "Parsed requests per repetition") { |value| operations = value.to_i }
  parser.on("--warmup=COUNT", "Warmup requests") { |value| warmup_operations = value.to_i }
  parser.on("--repetitions=COUNT", "Measured repetitions") { |value| repetitions = value.to_i }
  parser.on("--output=PATH", "JSON output path") { |value| output_path = value }
end

Amber::Benchmarks::RouterRevalidationHTTPCPU.run(route_count, operations, warmup_operations, repetitions, output_path)
