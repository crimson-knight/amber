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
  QUERY_RESOURCE            = "/bench/query?page=10&sort=asc&filter=active"
  JSON_BODY_RESOURCE        = "/bench/json-body"
  JSON_BODY_PAYLOAD         = %({"id":42,"name":"amber","active":true})
  QUERY_HYBRID_FILTER_FIELD = "filter"
  QUERY_HYBRID_FILTER_MSG   = "Filter must be active"
  JSON_HYBRID_NAME_FIELD    = "name"
  JSON_HYBRID_NAME_MSG      = "Name must be amber"

  @@sink = 0

  Amber::Validators::Params.compile QUERY_VALIDATION do
    required(:page)
    required(:sort)
    required(:filter)
  end

  Amber::Validators::Params.compile JSON_BODY_VALIDATION do
    required(:id)
    required(:name)
    required(:active)
  end

  Amber::Validators::Params.compile QUERY_HYBRID_VALIDATION do
    required(:page)
    required(:sort)
    required(QUERY_HYBRID_FILTER_FIELD, QUERY_HYBRID_FILTER_MSG) { |value| value == "active" }
  end

  Amber::Validators::Params.compile QUERY_PREDICATE_ONLY_VALIDATION do
    required(QUERY_HYBRID_FILTER_FIELD, QUERY_HYBRID_FILTER_MSG) { |value| value == "active" }
  end

  Amber::Validators::Params.compile JSON_BODY_HYBRID_VALIDATION do
    required(:id)
    required(JSON_HYBRID_NAME_FIELD, JSON_HYBRID_NAME_MSG) { |value| value == "amber" }
    required(:active)
  end

  class ::HTTP::Server::Context
    def bench_finalize_response!
      finalize_response!
    end
  end

  class QueryParamsController < Amber::Controller::Base
    def raw_index
      AmberFrameworkPerfProfile.consume(raw_params["page"].bytesize + raw_params["sort"].bytesize + raw_params["filter"].bytesize)
      set_response(AmberFrameworkPerfProfile::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfProfile::CONTENT_TEXT)
    end

    def index
      AmberFrameworkPerfProfile.consume(params["page"].bytesize + params["sort"].bytesize + params["filter"].bytesize)
      set_response(AmberFrameworkPerfProfile::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfProfile::CONTENT_TEXT)
    end

    def validated_index
      validated_params = params.validation do
        required(:page)
        required(:sort)
        required(:filter)
      end.validate!
      AmberFrameworkPerfProfile.consume(
        validated_params["page"].not_nil!.bytesize +
        validated_params["sort"].not_nil!.bytesize +
        validated_params["filter"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfProfile::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfProfile::CONTENT_TEXT)
    end

    def compiled_validated_index
      validated_params = legacy_params.validation(AmberFrameworkPerfProfile::QUERY_VALIDATION).validate!
      AmberFrameworkPerfProfile.consume(
        validated_params["page"].not_nil!.bytesize +
        validated_params["sort"].not_nil!.bytesize +
        validated_params["filter"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfProfile::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfProfile::CONTENT_TEXT)
    end

    def mixed_validated_index
      validated_params = params.validation do
        required(:page)
        required(:sort)
        required(AmberFrameworkPerfProfile::QUERY_HYBRID_FILTER_FIELD, AmberFrameworkPerfProfile::QUERY_HYBRID_FILTER_MSG) { |value| value == "active" }
      end.validate!
      AmberFrameworkPerfProfile.consume(
        validated_params["page"].not_nil!.bytesize +
        validated_params["sort"].not_nil!.bytesize +
        validated_params["filter"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfProfile::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfProfile::CONTENT_TEXT)
    end

    def hybrid_validated_index
      validated_params = legacy_params.validation(AmberFrameworkPerfProfile::QUERY_HYBRID_VALIDATION).validate!
      AmberFrameworkPerfProfile.consume(
        validated_params["page"].not_nil!.bytesize +
        validated_params["sort"].not_nil!.bytesize +
        validated_params["filter"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfProfile::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfProfile::CONTENT_TEXT)
    end

    def predicate_only_validated_index
      validated_params = params.validation do
        required(AmberFrameworkPerfProfile::QUERY_HYBRID_FILTER_FIELD, AmberFrameworkPerfProfile::QUERY_HYBRID_FILTER_MSG) { |value| value == "active" }
      end.validate!
      AmberFrameworkPerfProfile.consume(validated_params["filter"].not_nil!.bytesize)
      set_response(AmberFrameworkPerfProfile::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfProfile::CONTENT_TEXT)
    end

    def predicate_only_compiled_validated_index
      validated_params = legacy_params.validation(AmberFrameworkPerfProfile::QUERY_PREDICATE_ONLY_VALIDATION).validate!
      AmberFrameworkPerfProfile.consume(validated_params["filter"].not_nil!.bytesize)
      set_response(AmberFrameworkPerfProfile::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfProfile::CONTENT_TEXT)
    end
  end

  class JsonController < Amber::Controller::Base
    def negotiated
      respond_with do
        json(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY)
      end
    end
  end

  class JsonBodyController < Amber::Controller::Base
    def raw_create
      AmberFrameworkPerfProfile.consume(raw_params["id"].bytesize + raw_params["name"].bytesize + raw_params["active"].bytesize)
      set_response(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfProfile::CONTENT_JSON)
    end

    def create
      AmberFrameworkPerfProfile.consume(params["id"].bytesize + params["name"].bytesize + params["active"].bytesize)
      set_response(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfProfile::CONTENT_JSON)
    end

    def validated_create
      validated_params = params.validation do
        required(:id)
        required(:name)
        required(:active)
      end.validate!
      AmberFrameworkPerfProfile.consume(
        validated_params["id"].not_nil!.bytesize +
        validated_params["name"].not_nil!.bytesize +
        validated_params["active"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfProfile::CONTENT_JSON)
    end

    def compiled_validated_create
      validated_params = legacy_params.validation(AmberFrameworkPerfProfile::JSON_BODY_VALIDATION).validate!
      AmberFrameworkPerfProfile.consume(
        validated_params["id"].not_nil!.bytesize +
        validated_params["name"].not_nil!.bytesize +
        validated_params["active"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfProfile::CONTENT_JSON)
    end

    def mixed_validated_create
      validated_params = params.validation do
        required(:id)
        required(AmberFrameworkPerfProfile::JSON_HYBRID_NAME_FIELD, AmberFrameworkPerfProfile::JSON_HYBRID_NAME_MSG) { |value| value == "amber" }
        required(:active)
      end.validate!
      AmberFrameworkPerfProfile.consume(
        validated_params["id"].not_nil!.bytesize +
        validated_params["name"].not_nil!.bytesize +
        validated_params["active"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfProfile::CONTENT_JSON)
    end

    def hybrid_validated_create
      validated_params = legacy_params.validation(AmberFrameworkPerfProfile::JSON_BODY_HYBRID_VALIDATION).validate!
      AmberFrameworkPerfProfile.consume(
        validated_params["id"].not_nil!.bytesize +
        validated_params["name"].not_nil!.bytesize +
        validated_params["active"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfProfile::CONTENT_JSON)
    end
  end

  def consume(value : Int32)
    @@sink = value
  end

  def install_routes
    router = Amber::Server.router
    routes = [
      Amber::Route.new("GET", "/bench/json", ->(context : HTTP::Server::Context) { JsonController.new(context).negotiated }, :negotiated, :web, controller: "AmberFrameworkPerfProfile::JsonController"),
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

  def action_query_raw_params
    context = build_context("GET", QUERY_RESOURCE)
    QueryParamsController.new(context).raw_index
    context.bench_finalize_response!
  end

  def action_query_validated_params
    context = build_context("GET", QUERY_RESOURCE)
    QueryParamsController.new(context).validated_index
    context.bench_finalize_response!
  end

  def action_query_compiled_validated_params
    context = build_context("GET", QUERY_RESOURCE)
    QueryParamsController.new(context).compiled_validated_index
    context.bench_finalize_response!
  end

  def action_query_mixed_validated_params
    context = build_context("GET", QUERY_RESOURCE)
    QueryParamsController.new(context).mixed_validated_index
    context.bench_finalize_response!
  end

  def action_query_hybrid_validated_params
    context = build_context("GET", QUERY_RESOURCE)
    QueryParamsController.new(context).hybrid_validated_index
    context.bench_finalize_response!
  end

  def action_query_predicate_only_validated_params
    context = build_context("GET", QUERY_RESOURCE)
    QueryParamsController.new(context).predicate_only_validated_index
    context.bench_finalize_response!
  end

  def action_query_predicate_only_compiled_validated_params
    context = build_context("GET", QUERY_RESOURCE)
    QueryParamsController.new(context).predicate_only_compiled_validated_index
    context.bench_finalize_response!
  end

  def action_json_respond_with
    context = build_context("GET", "/bench/json", JSON_ACCEPT)
    JsonController.new(context).negotiated
    context.bench_finalize_response!
  end

  def dispatch_json(pipeline : Amber::Pipe::Pipeline)
    context = build_context("GET", "/bench/json", JSON_ACCEPT)
    pipeline.call(context)
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

  def action_json_body_raw_params
    context = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    JsonBodyController.new(context).raw_create
    context.bench_finalize_response!
  end

  def action_json_body_validated_params
    context = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    JsonBodyController.new(context).validated_create
    context.bench_finalize_response!
  end

  def action_json_body_compiled_validated_params
    context = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    JsonBodyController.new(context).compiled_validated_create
    context.bench_finalize_response!
  end

  def action_json_body_mixed_validated_params
    context = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    JsonBodyController.new(context).mixed_validated_create
    context.bench_finalize_response!
  end

  def action_json_body_hybrid_validated_params
    context = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    JsonBodyController.new(context).hybrid_validated_create
    context.bench_finalize_response!
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

  parser.on("--scenario=NAME", "Scenario: action_query_params, action_query_raw_params, action_query_validated_params, action_query_compiled_validated_params, action_query_mixed_validated_params, action_query_hybrid_validated_params, action_query_predicate_only_validated_params, action_query_predicate_only_compiled_validated_params, action_json_respond_with, dispatch_json, params_lookup_query, dispatch_json_body, action_json_body_raw_params, action_json_body_validated_params, action_json_body_compiled_validated_params, action_json_body_mixed_validated_params, action_json_body_hybrid_validated_params, params_lookup_json") do |value|
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
                when "action_query_raw_params"
                  -> { AmberFrameworkPerfProfile.action_query_raw_params }
                when "action_query_validated_params"
                  -> { AmberFrameworkPerfProfile.action_query_validated_params }
                when "action_query_compiled_validated_params"
                  -> { AmberFrameworkPerfProfile.action_query_compiled_validated_params }
                when "action_query_mixed_validated_params"
                  -> { AmberFrameworkPerfProfile.action_query_mixed_validated_params }
                when "action_query_hybrid_validated_params"
                  -> { AmberFrameworkPerfProfile.action_query_hybrid_validated_params }
                when "action_query_predicate_only_validated_params"
                  -> { AmberFrameworkPerfProfile.action_query_predicate_only_validated_params }
                when "action_query_predicate_only_compiled_validated_params"
                  -> { AmberFrameworkPerfProfile.action_query_predicate_only_compiled_validated_params }
                when "action_json_respond_with"
                  -> { AmberFrameworkPerfProfile.action_json_respond_with }
                when "dispatch_json"
                  -> { AmberFrameworkPerfProfile.dispatch_json(pipeline) }
                when "params_lookup_query"
                  -> { AmberFrameworkPerfProfile.params_lookup_query }
                when "dispatch_json_body"
                  -> { AmberFrameworkPerfProfile.dispatch_json_body(pipeline) }
                when "action_json_body_raw_params"
                  -> { AmberFrameworkPerfProfile.action_json_body_raw_params }
                when "action_json_body_validated_params"
                  -> { AmberFrameworkPerfProfile.action_json_body_validated_params }
                when "action_json_body_compiled_validated_params"
                  -> { AmberFrameworkPerfProfile.action_json_body_compiled_validated_params }
                when "action_json_body_mixed_validated_params"
                  -> { AmberFrameworkPerfProfile.action_json_body_mixed_validated_params }
                when "action_json_body_hybrid_validated_params"
                  -> { AmberFrameworkPerfProfile.action_json_body_hybrid_validated_params }
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
