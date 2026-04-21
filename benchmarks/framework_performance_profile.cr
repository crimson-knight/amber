require "option_parser"
require "../src/amber"

module AmberFrameworkPerfProfile
  extend self

  CONTENT_JSON = Amber::Controller::Helpers::Responders::Content::TYPE[:json]
  CONTENT_TEXT = Amber::Controller::Helpers::Responders::Content::TYPE[:text]
  JSON_ACCEPT  = HTTP::Headers{"Accept" => "application/json"}
  JSON_HEADERS = HTTP::Headers{
    "Accept"       => "application/json",
    "Content-Type" => "application/json",
  }

  PLAIN_TEXT_RESPONSE = "ok"
  JSON_RESPONSE_BODY  = {
    "status"    => "ok",
    "framework" => "amber",
    "version"   => "2",
  }.to_json
  QUERY_RESOURCE     = "/bench/query?page=10&sort=asc&filter=active"
  JSON_BODY_RESOURCE = "/bench/json-body"
  JSON_BODY_PAYLOAD  = %({"id":42,"name":"amber","active":true})

  @@sink = 0

  class ::HTTP::Server::Context
    def bench_finalize_response!
      finalize_response!
    end
  end

  class QueryParamsController < Amber::Controller::Base
    def index
      AmberFrameworkPerfProfile.consume(params["page"].bytesize + params["sort"].bytesize + params["filter"].bytesize)
      set_response(AmberFrameworkPerfProfile::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfProfile::CONTENT_TEXT)
    end
  end

  class JsonBodyController < Amber::Controller::Base
    def create
      AmberFrameworkPerfProfile.consume(params["id"].bytesize + params["name"].bytesize + params["active"].bytesize)
      set_response(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfProfile::CONTENT_JSON)
    end
  end

  def consume(value : Int32)
    @@sink = value
  end

  def install_routes
    router = Amber::Server.router
    routes = [
      Amber::Route.new("GET", "/bench/query", ->(context : HTTP::Server::Context) { QueryParamsController.new(context).index }, :index, :web, controller: "AmberFrameworkPerfProfile::QueryParamsController"),
      Amber::Route.new("POST", "/bench/json-body", ->(context : HTTP::Server::Context) { JsonBodyController.new(context).create }, :create, :web, controller: "AmberFrameworkPerfProfile::JsonBodyController"),
    ]

    routes.each { |route| router.add(route) }
  end

  def build_pipeline : Amber::Pipe::Pipeline
    pipeline = Amber::Pipe::Pipeline.new
    pipeline.prepare_pipelines
    pipeline
  end

  def build_context(method : String, resource : String, headers : HTTP::Headers = HTTP::Headers.new, body = "") : HTTP::Server::Context
    request = HTTP::Request.new(method, resource, headers, body)
    response = HTTP::Server::Response.new(IO::Memory.new)
    HTTP::Server::Context.new(request, response)
  end

  def action_query_params
    context = build_context("GET", QUERY_RESOURCE)
    QueryParamsController.new(context).index
    context.bench_finalize_response!
  end

  def params_lookup_query
    context = build_context("GET", QUERY_RESOURCE)
    params = context.params
    consume(params["page"].bytesize + params["sort"].bytesize + params["filter"].bytesize)
  end

  def dispatch_json_body(pipeline : Amber::Pipe::Pipeline)
    context = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    pipeline.call(context)
  end

  def params_lookup_json
    context = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    params = context.params
    consume(params["id"].bytesize + params["name"].bytesize + params["active"].bytesize)
  end
end

scenario = "action_query_params"
duration_seconds = 20.0

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal run benchmarks/framework_performance_profile.cr -- [options]"

  parser.on("--scenario=NAME", "Scenario: action_query_params, params_lookup_query, dispatch_json_body, params_lookup_json") do |value|
    scenario = value
  end

  parser.on("--duration=SECONDS", "Wall-clock run duration (default: #{duration_seconds})") do |value|
    duration_seconds = value.to_f
  end
end

AmberFrameworkPerfProfile.install_routes
pipeline = AmberFrameworkPerfProfile.build_pipeline

scenario_proc = case scenario
                when "action_query_params"
                  -> { AmberFrameworkPerfProfile.action_query_params }
                when "params_lookup_query"
                  -> { AmberFrameworkPerfProfile.params_lookup_query }
                when "dispatch_json_body"
                  -> { AmberFrameworkPerfProfile.dispatch_json_body(pipeline) }
                when "params_lookup_json"
                  -> { AmberFrameworkPerfProfile.params_lookup_json }
                else
                  raise "Unknown scenario: #{scenario}"
                end

deadline = Time.instant + duration_seconds.seconds
iterations = 0_u64

STDOUT.sync = true
puts "Amber framework profile harness"
puts "PID: #{Process.pid}"
puts "Scenario: #{scenario}"
puts "Duration: #{duration_seconds}s"

while Time.instant < deadline
  scenario_proc.call
  iterations += 1
end

puts "Iterations: #{iterations}"
