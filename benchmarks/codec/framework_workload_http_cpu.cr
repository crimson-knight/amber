require "json"
require "msgpack"
require "option_parser"
require "../../src/amber"
require "../router_revalidation_support"

module Amber::Benchmarks::FrameworkWorkload
  extend self

  CONTENT_JSON    = "application/json; charset=utf-8"
  CONTENT_MSGPACK = "application/vnd.msgpack"
  STATIC_BODY     = %({"status":"ok","framework":"amber","route":"static"})
  CODEC_MODE      = {% if flag?(:amber_bench_typed_json) %}
    "typed_json"
  {% elsif flag?(:amber_bench_msgpack_map) %}
    "msgpack_map"
  {% elsif flag?(:amber_bench_msgpack_array) %}
    "msgpack_array"
  {% else %}
    "legacy_json_params"
  {% end %} + {% if flag?(:amber_bench_buffer_body) %}
    "_buffered"
  {% else %}
    "_streaming"
  {% end %}

  REQUEST_ID = "01J8Z3M5N70000000000421987"
  ACCOUNT_ID = "018f1e2d-3c4b-7a69-8f01-000000004219"
  EMAIL      = "performance@example.com"
  NOTE       = "Created from the mobile checkout flow"
  TAGS       = ["mobile", "priority", "returning"]

  class JsonPayload
    include JSON::Serializable

    getter request_id : String
    getter account_id : String
    getter email : String
    getter quantity : Int32
    getter active : Bool
    getter priority : Int32
    getter tags : Array(String)
    getter note : String

    def initialize(
      @request_id,
      @account_id,
      @email,
      @quantity,
      @active,
      @priority,
      @tags,
      @note,
    )
    end
  end

  class MsgpackMapPayload
    include MessagePack::Serializable

    getter request_id : String
    getter account_id : String
    getter email : String
    getter quantity : Int32
    getter active : Bool
    getter priority : Int32
    getter tags : Array(String)
    getter note : String

    def initialize(
      @request_id,
      @account_id,
      @email,
      @quantity,
      @active,
      @priority,
      @tags,
      @note,
    )
    end
  end

  class MsgpackArrayPayload
    include MessagePack::ArraySerializable

    getter request_id : String
    getter account_id : String
    getter email : String
    getter quantity : Int32
    getter active : Bool
    getter priority : Int32
    getter tags : Array(String)
    getter note : String

    def initialize(
      @request_id,
      @account_id,
      @email,
      @quantity,
      @active,
      @priority,
      @tags,
      @note,
    )
    end
  end

  record DecodedPayload,
    request_id : String,
    account_id : String,
    email : String,
    quantity : Int32,
    active : Bool,
    priority : Int32,
    tag_count : Int32,
    note : String

  record WorkloadRoute,
    definition : RouterRevalidation::RouteDefinition,
    method : String

  record TrafficRequest,
    route : WorkloadRoute,
    resource : String

  alias Body = String | Bytes
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

  JSON_PAYLOAD          = JsonPayload.new(REQUEST_ID, ACCOUNT_ID, EMAIL, 7, true, 3, TAGS, NOTE)
  MSGPACK_MAP_PAYLOAD   = MsgpackMapPayload.new(REQUEST_ID, ACCOUNT_ID, EMAIL, 7, true, 3, TAGS, NOTE)
  MSGPACK_ARRAY_PAYLOAD = MsgpackArrayPayload.new(REQUEST_ID, ACCOUNT_ID, EMAIL, 7, true, 3, TAGS, NOTE)

  JSON_BODY          = JSON_PAYLOAD.to_json
  MSGPACK_MAP_BODY   = MSGPACK_MAP_PAYLOAD.to_msgpack
  MSGPACK_ARRAY_BODY = MSGPACK_ARRAY_PAYLOAD.to_msgpack

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
    def read_response(kind : Symbol) : Nil
      case kind
      when :static
        set_response(STATIC_BODY, 200, CONTENT_JSON)
      when :nested
        id = params["id"]? || "missing"
        child_id = params["child_id"]? || "missing"
        set_response(String.build(112) { |io| io << %({"id":); id.to_json(io); io << %(,"child_id":); child_id.to_json(io); io << '}' }, 200, CONTENT_JSON)
      when :glob
        path = params["path"]? || "missing"
        set_response(String.build(96) { |io| io << %({"path":); path.to_json(io); io << '}' }, 200, CONTENT_JSON)
      else
        id = params["id"]? || "missing"
        set_response(String.build(96) { |io| io << %({"id":); id.to_json(io); io << '}' }, 200, CONTENT_JSON)
      end
    end

    def write_response : Nil
      payload = decode_payload
      body = String.build(128) do |io|
        io << %({"request_id":)
        payload.request_id.to_json(io)
        io << %(,"account_id":)
        payload.account_id.to_json(io)
        io << %(,"quantity":) << payload.quantity
        io << %(,"active":) << payload.active
        io << %(,"tags":) << payload.tag_count << '}'
      end
      set_response(body, 200, CONTENT_JSON)
    end

    private def decode_payload : DecodedPayload
      {% if flag?(:amber_bench_typed_json) %}
        input = context.request.body.not_nil!
        payload = {% if flag?(:amber_bench_buffer_body) %}
                    JsonPayload.from_json(input.gets_to_end)
                  {% else %}
                    JsonPayload.from_json(input)
                  {% end %}
        DecodedPayload.new(payload.request_id, payload.account_id, payload.email, payload.quantity, payload.active, payload.priority, payload.tags.size, payload.note)
      {% elsif flag?(:amber_bench_msgpack_map) %}
        input = context.request.body.not_nil!
        payload = {% if flag?(:amber_bench_buffer_body) %}
                    MsgpackMapPayload.from_msgpack(input.gets_to_end)
                  {% else %}
                    MsgpackMapPayload.from_msgpack(input)
                  {% end %}
        DecodedPayload.new(payload.request_id, payload.account_id, payload.email, payload.quantity, payload.active, payload.priority, payload.tags.size, payload.note)
      {% elsif flag?(:amber_bench_msgpack_array) %}
        input = context.request.body.not_nil!
        payload = {% if flag?(:amber_bench_buffer_body) %}
                    MsgpackArrayPayload.from_msgpack(input.gets_to_end)
                  {% else %}
                    MsgpackArrayPayload.from_msgpack(input)
                  {% end %}
        DecodedPayload.new(payload.request_id, payload.account_id, payload.email, payload.quantity, payload.active, payload.priority, payload.tags.size, payload.note)
      {% else %}
        tag_count = params.json("tags").as_a.size
        DecodedPayload.new(
          params["request_id"],
          params["account_id"],
          params["email"],
          params["quantity"].to_i32,
          params["active"] == "true",
          params["priority"].to_i32,
          tag_count,
          params["note"]
        )
      {% end %}
    end
  end

  def method_for_percentile(percentile : Int32) : String
    case percentile
    when 0..39  then "GET"
    when 40..69 then "POST"
    when 70..84 then "PUT"
    when 85..94 then "PATCH"
    else             "DELETE"
    end
  end

  def handler_for(method : String, kind : Symbol) : HTTP::Server::Context ->
    if method.in?("POST", "PUT", "PATCH")
      ->(context : HTTP::Server::Context) { Controller.new(context).write_response }
    else
      ->(context : HTTP::Server::Context) { Controller.new(context).read_response(kind) }
    end
  end

  def workload_routes(count : Int32) : Array(WorkloadRoute)
    definitions = RouterRevalidation.generate_routes(count)
    totals = definitions.each_with_object(Hash(Symbol, Int32).new(0)) { |definition, result| result[definition.kind] += 1 }
    indexes = Hash(Symbol, Int32).new(0)

    definitions.map do |definition|
      shape_index = indexes[definition.kind]
      indexes[definition.kind] += 1
      percentile = shape_index * 100 // totals[definition.kind]
      method = method_for_percentile(percentile)
      WorkloadRoute.new(definition, method)
    end
  end

  def install_routes(count : Int32) : Array(WorkloadRoute)
    routes = workload_routes(count)
    routes.each do |route|
      definition = route.definition
      method = route.method
      Amber::Server.router.add(
        Amber::Route.new(
          method,
          definition.resource,
          handler_for(method, definition.kind),
          method.in?("POST", "PUT", "PATCH") ? :write : :read,
          :web,
          Amber::Router::Scope.new,
          "Amber::Benchmarks::FrameworkWorkload::Controller",
          definition.constraints
        )
      )
    end
    routes
  end

  def requested_method(profile : Symbol, percentile : Int32) : String
    case profile
    when :read_heavy
      case percentile
      when 0..64  then "GET"
      when 65..84 then "POST"
      when 85..92 then "PUT"
      when 93..97 then "PATCH"
      else             "DELETE"
      end
    when :balanced
      case percentile
      when 0..39  then "GET"
      when 40..69 then "POST"
      when 70..84 then "PUT"
      when 85..94 then "PATCH"
      else             "DELETE"
      end
    when :write_heavy
      case percentile
      when 0..19  then "GET"
      when 20..59 then "POST"
      when 60..79 then "PUT"
      when 80..94 then "PATCH"
      else             "DELETE"
      end
    else
      raise ArgumentError.new("unknown workload profile: #{profile}")
    end
  end

  def profile_from_string(name : String) : Symbol
    case name
    when "read_heavy"  then :read_heavy
    when "balanced"    then :balanced
    when "write_heavy" then :write_heavy
    else                    raise ArgumentError.new("unknown workload profile: #{name}")
    end
  end

  def requested_shape(percentile : Int32) : Symbol
    case percentile
    when 0..44  then :static
    when 45..69 then :restful
    when 70..84 then :variable
    when 85..89 then :nested
    when 90..94 then :constrained
    else             :glob
    end
  end

  def generate_traffic(routes : Array(WorkloadRoute), profile : Symbol, size = 4096) : Array(TrafficRequest)
    routes_by_cell = routes.group_by { |route| {route.method, route.definition.kind} }
    Array(TrafficRequest).new(size) do |index|
      method = requested_method(profile, index % 100)
      shape = requested_shape((index * 37 + index // 100 * 13) % 100)
      pool = routes_by_cell[{method, shape}]
      hot_size = Math.max(pool.size // 5, 1)
      route_index = if index % 10 < 7
                      (index * 17 + index // 100) % hot_size
                    else
                      (index * 43 + 11) % pool.size
                    end
      route = pool[route_index]
      style = route.definition.constraint_style || RouterRevalidation::IDENTIFIER_STYLES[(index // 7) % RouterRevalidation::IDENTIFIER_STYLES.size]
      resource = route.definition.matching_resource(index, style)
      resource += "?include=profile&page=#{index % 11}" if index % 5 == 0
      TrafficRequest.new(route, resource)
    end
  end

  def request_body : Body
    {% if flag?(:amber_bench_msgpack_map) %}
      MSGPACK_MAP_BODY
    {% elsif flag?(:amber_bench_msgpack_array) %}
      MSGPACK_ARRAY_BODY
    {% else %}
      JSON_BODY
    {% end %}
  end

  def request_content_type : String
    {% if flag?(:amber_bench_msgpack_map) || flag?(:amber_bench_msgpack_array) %}
      CONTENT_MSGPACK
    {% else %}
      CONTENT_JSON
    {% end %}
  end

  def build_request_stream(traffic : Array(TrafficRequest), operations : Int32) : String
    body = request_body
    String.build(operations * 320) do |io|
      operations.times do |index|
        request = traffic[index % traffic.size]
        method = request.route.method
        io << method << ' ' << request.resource << " HTTP/1.1\r\n"
        io << "Host: amber.local\r\n"
        io << "Accept: application/json\r\n"
        io << "User-Agent: amber-framework-workload\r\n"
        if method.in?("POST", "PUT", "PATCH")
          io << "Content-Type: " << request_content_type << "\r\n"
          io << "Content-Length: " << body.bytesize << "\r\n\r\n"
          io.write(body.to_slice)
        else
          io << "\r\n"
        end
      end
    end
  end

  def process_stream(pipeline : Amber::Pipe::Pipeline, raw_requests : String, memory_output = false) : IO
    input = IO::Memory.new(raw_requests)
    output = memory_output ? IO::Memory.new : CountingIO.new
    HTTP::Server::RequestProcessor.new(pipeline).process(input, output)
    output
  end

  def verify(pipeline : Amber::Pipe::Pipeline, traffic : Array(TrafficRequest)) : Nil
    output = process_stream(pipeline, build_request_stream(traffic, 100), memory_output: true).as(IO::Memory)
    responses = output.to_s
    count = responses.scan(/HTTP\/1\.1 200 OK/).size
    raise "expected 100 successful responses, got #{count}" unless count == 100
    raise "write response did not consume decoded fields" unless responses.includes?(REQUEST_ID)
  end

  def measure(pipeline : Amber::Pipe::Pipeline, raw_requests : String, operations : Int32, repetition : Int32) : Measurement
    GC.collect
    before = GC.stats
    started_at = Time.instant
    output = process_stream(pipeline, raw_requests).as(CountingIO)
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

  def counts(traffic : Array(TrafficRequest), &block : TrafficRequest -> String) : Hash(String, Int32)
    traffic.each_with_object(Hash(String, Int32).new(0)) do |request, result|
      key = yield request
      result[key] += 1
    end
  end

  def lua_binary(bytes : Bytes) : String
    String.build(bytes.size * 4) do |io|
      bytes.each do |byte|
        io << '\\' << byte.to_s.rjust(3, '0')
      end
    end
  end

  def emit_wrk_script(path : String, route_count : Int32, profile : Symbol, traffic_size : Int32) : Nil
    routes = workload_routes(route_count)
    traffic = generate_traffic(routes, profile, traffic_size)
    body = request_body
    script = String.build(traffic.size * 128 + body.bytesize * 4 + 1024) do |io|
      io << "local payload = \"" << lua_binary(body.to_slice) << "\"\n"
      io << "local read_headers = { [\"Accept\"] = \"application/json\" }\n"
      io << "local write_headers = { [\"Accept\"] = \"application/json\", [\"Content-Type\"] = \"" << request_content_type << "\" }\n"
      io << "local requests = {\n"
      traffic.each do |request|
        has_body = request.route.method.in?("POST", "PUT", "PATCH")
        io << "  { " << request.route.method.to_json << ", " << request.resource.to_json << ", " << has_body << " },\n"
      end
      io << "}\n"
      io << <<-'LUA'
local index = 0

request = function()
  index = (index % #requests) + 1
  local entry = requests[index]
  if entry[3] then
    return wrk.format(entry[1], entry[2], write_headers, payload)
  end
  return wrk.format(entry[1], entry[2], read_headers)
end
LUA
    end
    File.write(path, script)
    puts "Wrote #{path} (#{traffic.size} requests, #{body.bytesize}-byte #{CODEC_MODE} payload)"
  end

  def serve(host : String, port : Int32, route_count : Int32) : Nil
    install_routes(route_count)
    pipeline = Amber::Pipe::Pipeline.new
    pipeline.prepare_pipelines
    server = HTTP::Server.new(pipeline)
    address = server.bind_tcp(host, port)
    Signal::INT.trap { server.close }
    Signal::TERM.trap { server.close }
    puts "READY #{address} routes=#{route_count} codec=#{CODEC_MODE}"
    STDOUT.flush
    server.listen
  end

  def run(
    route_count : Int32,
    operations : Int32,
    warmup_operations : Int32,
    repetitions : Int32,
    traffic_size : Int32,
    profile : Symbol,
    output_path : String,
  ) : Nil
    routes = install_routes(route_count)
    traffic = generate_traffic(routes, profile, traffic_size)
    pipeline = Amber::Pipe::Pipeline.new
    pipeline.prepare_pipelines
    verify(pipeline, traffic)

    process_stream(pipeline, build_request_stream(traffic, warmup_operations))
    raw_requests = build_request_stream(traffic, operations)
    measurements = Array(Measurement).new(repetitions)
    repetitions.times do |index|
      measurement = measure(pipeline, raw_requests, operations, index + 1)
      measurements << measurement
      puts "r#{index + 1} | #{measurement[:requests_per_second].round.to_i} req/s | #{measurement[:ns_per_request].round(1)} ns/request | #{measurement[:bytes_per_request].round(1)} B/request"
    end

    middle = repetitions // 2
    method_counts = counts(traffic, &.route.method)
    shape_counts = counts(traffic) { |request| request.route.definition.kind.to_s }
    route_method_counts = routes.each_with_object(Hash(String, Int32).new(0)) { |route, result| result[route.method] += 1 }
    route_shape_counts = routes.each_with_object(Hash(String, Int32).new(0)) { |route, result| result[route.definition.kind.to_s] += 1 }
    payload = {
      metadata: {
        compiler:                   Crystal::DESCRIPTION,
        generated_at_utc:           Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
        codec_mode:                 CODEC_MODE,
        route_count:                route_count,
        route_method_counts:        route_method_counts,
        route_shape_counts:         route_shape_counts,
        traffic_profile:            profile,
        traffic_entries:            traffic.size,
        sampled_method_counts:      method_counts,
        sampled_route_shape_counts: shape_counts,
        traffic_locality:           "70% selects the first 20% of each method's route pool; 20% query strings",
        operations:                 operations,
        warmup_operations:          warmup_operations,
        repetitions:                repetitions,
        request_payload_fields:     8,
        request_payload_bytes:      request_body.bytesize,
        buffered_request_body:      {{flag?(:amber_bench_buffer_body)}},
        response_behavior:          "reads consume route params; writes consume every body field and emit a JSON acknowledgement",
        http_scope:                 "Crystal HTTP/1.1 parser and serializer plus full Amber pipeline; excludes sockets and kernel scheduling",
        legacy_request_method:      {{flag?(:amber_bench_legacy_request_method)}},
        legacy_keep_alive_headers:  {{flag?(:amber_bench_legacy_keep_alive_headers)}},
      },
      summary: {
        median_requests_per_second: measurements.map(&.[:requests_per_second]).sort[middle],
        median_ns_per_request:      measurements.map(&.[:ns_per_request]).sort[middle],
        median_bytes_per_request:   measurements.map(&.[:bytes_per_request]).sort[middle],
        response_bytes_per_request: measurements.map(&.[:response_bytes_per_request]).sort[middle],
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
repetitions = 7
traffic_size = 4096
profile = :read_heavy
output_path = "../results/round22_framework_workload.json"
server_mode = false
host = "127.0.0.1"
port = 8080
wrk_script_path = nil

OptionParser.parse do |parser|
  parser.banner = "Usage: framework_workload_http_cpu [options]"
  parser.on("--routes=COUNT", "Routes in the application table") { |value| route_count = value.to_i }
  parser.on("--operations=COUNT", "Parsed requests per repetition") { |value| operations = value.to_i }
  parser.on("--warmup=COUNT", "Warmup requests") { |value| warmup_operations = value.to_i }
  parser.on("--repetitions=COUNT", "Measured repetitions") { |value| repetitions = value.to_i }
  parser.on("--traffic-size=COUNT", "Deterministic traffic entries") { |value| traffic_size = value.to_i }
  parser.on("--profile=NAME", "read_heavy, balanced, or write_heavy") { |value| profile = Amber::Benchmarks::FrameworkWorkload.profile_from_string(value) }
  parser.on("--output=PATH", "JSON result path") { |value| output_path = value }
  parser.on("--server", "Run the socket server instead of the CPU benchmark") { server_mode = true }
  parser.on("--host=HOST", "Server bind host") { |value| host = value }
  parser.on("--port=PORT", "Server bind port") { |value| port = value.to_i }
  parser.on("--emit-wrk-script=PATH", "Write the deterministic mixed-request wrk script") { |value| wrk_script_path = value }
end

if script_path = wrk_script_path
  Amber::Benchmarks::FrameworkWorkload.emit_wrk_script(script_path, route_count, profile, traffic_size)
elsif server_mode
  Amber::Benchmarks::FrameworkWorkload.serve(host, port, route_count)
else
  Amber::Benchmarks::FrameworkWorkload.run(
    route_count,
    operations,
    warmup_operations,
    repetitions,
    traffic_size,
    profile,
    output_path
  )
end
