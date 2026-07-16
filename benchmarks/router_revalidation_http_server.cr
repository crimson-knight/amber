require "option_parser"
require "../src/amber"
require "./router_revalidation_support"

module Amber::Benchmarks::RouterRevalidationHTTP
  extend self

  CONTENT_JSON = "application/json; charset=utf-8"
  STATIC_BODY  = %({"status":"ok","framework":"amber","route":"static"})
  STRATEGY     = {% if flag?(:amber_router_legacy_match) %}
                   "current_match"
                 {% elsif flag?(:amber_router_best_match) %}
                   "best_match"
                 {% else %}
                   "span_match"
                 {% end %}

  class Controller < Amber::Controller::Base
    def static_response
      exercise_optional_params
      render_json(STATIC_BODY)
    end

    def dynamic_response
      exercise_optional_params
      id = params["id"]? || "missing"
      body = String.build(96) do |io|
        io << "{\"status\":\"ok\",\"framework\":\"amber\",\"id\":"
        id.to_json(io)
        io << '}'
      end
      render_json(body)
    end

    def nested_response
      exercise_optional_params
      id = params["id"]? || "missing"
      child_id = params["child_id"]? || "missing"
      body = String.build(112) do |io|
        io << "{\"status\":\"ok\",\"framework\":\"amber\",\"id\":"
        id.to_json(io)
        io << ",\"child_id\":"
        child_id.to_json(io)
        io << '}'
      end
      render_json(body)
    end

    def glob_response
      exercise_optional_params
      path = params["path"]? || "missing"
      body = String.build(128) do |io|
        io << "{\"status\":\"ok\",\"framework\":\"amber\",\"path\":"
        path.to_json(io)
        io << '}'
      end
      render_json(body)
    end

    private def exercise_optional_params : Nil
      {% if flag?(:amber_bench_optional_params) %}
        params["include"]?
        params["missing_optional"]?
      {% end %}
    end

    private def render_json(body : String)
      {% if flag?(:amber_bench_respond_with) %}
        respond_with do
          json body
        end
      {% else %}
        set_response(body, 200, CONTENT_JSON)
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
    definitions = RouterRevalidation.generate_routes(count)
    definitions.each do |definition|
      route = Amber::Route.new(
        "GET",
        definition.resource,
        handler_for(definition.kind),
        :show,
        :web,
        Amber::Router::Scope.new,
        "Amber::Benchmarks::RouterRevalidationHTTP::Controller",
        definition.constraints
      )
      Amber::Server.router.add(route)
    end
    definitions
  end

  def write_urls(path : String, definitions : Array(RouterRevalidation::RouteDefinition), host : String, port : Int32) : Nil
    traffic = RouterRevalidation.generate_traffic(definitions, include_misses: false)
    File.open(path, "w") do |file|
      traffic.each_with_index do |request, index|
        resource = request.path.lchop("get")
        query = index % 5 == 0 ? "?include=profile&page=#{index % 11}" : ""
        file.puts "http://#{host}:#{port}#{resource}#{query}"
      end
    end
  end

  def run(host : String, port : Int32, route_count : Int32, url_file : String?) : Nil
    definitions = install_routes(route_count)
    write_urls(url_file, definitions, host, port) if url_file

    pipeline = Amber::Pipe::Pipeline.new
    pipeline.prepare_pipelines
    server = HTTP::Server.new(pipeline)
    server.bind_tcp(host, port, false)

    Signal::INT.trap { server.close }
    Signal::TERM.trap { server.close }
    puts "READY host=#{host} port=#{port} routes=#{route_count} strategy=#{STRATEGY} compiler=#{Crystal::DESCRIPTION}"
    STDOUT.flush
    server.listen
  end
end

host = "127.0.0.1"
port = 41019
route_count = 1000
url_file : String? = nil

OptionParser.parse do |parser|
  parser.banner = "Usage: router_revalidation_http_server [options]"
  parser.on("--host=HOST", "Bind host") { |value| host = value }
  parser.on("--port=PORT", "Bind port") { |value| port = value.to_i }
  parser.on("--routes=COUNT", "Number of GET routes") { |value| route_count = value.to_i }
  parser.on("--url-file=PATH", "Write a mixed-traffic URL file") { |value| url_file = value }
end

Amber::Benchmarks::RouterRevalidationHTTP.run(host, port, route_count, url_file)
