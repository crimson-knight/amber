require "option_parser"
require "../src/amber"

module AmberFrameworkPerfProfile
  extend self

  CONTENT_JSON         = Amber::Controller::Helpers::Responders::Content::TYPE[:json]
  CONTENT_HTML         = Amber::Controller::Helpers::Responders::Content::TYPE[:html]
  CONTENT_TEXT         = Amber::Controller::Helpers::Responders::Content::TYPE[:text]
  JSON_ACCEPT          = HTTP::Headers{"Accept" => "application/json"}
  HTML_ACCEPT          = HTTP::Headers{"Accept" => "text/html"}
  JSON_WILDCARD_ACCEPT = HTTP::Headers{"Accept" => "application/json,*/*"}
  JSON_HEADERS         = HTTP::Headers{
    "Accept"       => "application/json",
    "Content-Type" => "application/json",
  }

  PLAIN_TEXT_RESPONSE = "ok"
  HTML_RESPONSE_BODY  = "<html><body><h1>Amber</h1></body></html>"
  XML_RESPONSE_BODY   = "<xml><body><h1>Amber</h1></body></xml>"
  JS_RESPONSE_BODY    = "console.log('amber')"
  HEAVY_HTML_REPEAT   = 128
  JSON_RESPONSE_BODY  = {
    "status"    => "ok",
    "framework" => "amber",
    "version"   => "2",
  }.to_json
  JSON_RESPONSE_NAMED_TUPLE = {
    status:    "ok",
    framework: "amber",
    version:   "2",
  }
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

  class PlaintextController < Amber::Controller::Base
    def index
      set_response(AmberFrameworkPerfProfile::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfProfile::CONTENT_TEXT)
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

  class RouteQueryController < Amber::Controller::Base
    def show
      AmberFrameworkPerfProfile.consume(params["id"].bytesize + params["page"].bytesize + params["sort"].bytesize + params["filter"].bytesize)
      set_response(AmberFrameworkPerfProfile::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfProfile::CONTENT_TEXT)
    end
  end

  class JsonController < Amber::Controller::Base
    def direct
      set_response(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfProfile::CONTENT_JSON)
    end

    def negotiated
      respond_with do
        json(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY)
      end
    end
  end

  class HtmlController < Amber::Controller::Base
    def direct
      set_response(AmberFrameworkPerfProfile::HTML_RESPONSE_BODY, 200, AmberFrameworkPerfProfile::CONTENT_HTML)
    end
  end

  class MultiFormatController < Amber::Controller::Base
    def negotiated
      respond_with do
        html(AmberFrameworkPerfProfile::HTML_RESPONSE_BODY)
        json(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY)
        xml(AmberFrameworkPerfProfile::XML_RESPONSE_BODY)
        text(AmberFrameworkPerfProfile::PLAIN_TEXT_RESPONSE)
        js(AmberFrameworkPerfProfile::JS_RESPONSE_BODY)
      end
    end

    def negotiated_runtime
      respond_with_runtime do
        html(AmberFrameworkPerfProfile::HTML_RESPONSE_BODY)
        json(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY)
        xml(AmberFrameworkPerfProfile::XML_RESPONSE_BODY)
        text(AmberFrameworkPerfProfile::PLAIN_TEXT_RESPONSE)
        js(AmberFrameworkPerfProfile::JS_RESPONSE_BODY)
      end
    end

    def heavy_negotiated
      respond_with do
        html(AmberFrameworkPerfProfile.expensive_html_response_body)
        json(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY)
      end
    end

    def heavy_negotiated_runtime
      respond_with_runtime do
        html(AmberFrameworkPerfProfile.expensive_html_response_body)
        json(AmberFrameworkPerfProfile::JSON_RESPONSE_BODY)
      end
    end
  end

  class SchemaJsonController < Amber::Controller::Base
    def named_tuple
      respond_with(AmberFrameworkPerfProfile::JSON_RESPONSE_NAMED_TUPLE)
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

  def expensive_html_response_body
    String.build(HTML_RESPONSE_BODY.bytesize * HEAVY_HTML_REPEAT) do |io|
      HEAVY_HTML_REPEAT.times do |index|
        io << HTML_RESPONSE_BODY
        io << index
      end
    end
  end

  def install_routes
    router = Amber::Server.router
    routes = [
      Amber::Route.new("GET", "/bench/plaintext", ->(context : HTTP::Server::Context) { PlaintextController.new(context).index }, :index, :web, controller: "AmberFrameworkPerfProfile::PlaintextController"),
      Amber::Route.new("GET", "/bench/json", ->(context : HTTP::Server::Context) { JsonController.new(context).negotiated }, :negotiated, :web, controller: "AmberFrameworkPerfProfile::JsonController"),
      Amber::Route.new("GET", "/bench/users/:id", ->(context : HTTP::Server::Context) { RouteQueryController.new(context).show }, :show, :web, controller: "AmberFrameworkPerfProfile::RouteQueryController"),
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

  def raw_plaintext
    context = build_context("GET", "/raw/plaintext")
    context.response.status_code = 200
    context.response.content_type = CONTENT_TEXT
    context.response.print(PLAIN_TEXT_RESPONSE)
  end

  def action_plaintext
    context = build_context("GET", "/bench/plaintext")
    PlaintextController.new(context).index
    context.bench_finalize_response!
  end

  def raw_json
    context = build_context("GET", "/raw/json", JSON_ACCEPT)
    context.response.status_code = 200
    context.response.content_type = CONTENT_JSON
    context.response.print(JSON_RESPONSE_BODY)
  end

  def action_json_direct
    context = build_context("GET", "/bench/json", JSON_ACCEPT)
    JsonController.new(context).direct
    context.bench_finalize_response!
  end

  def action_json_direct_no_accept
    context = build_context("GET", "/bench/json")
    JsonController.new(context).direct
    context.bench_finalize_response!
  end

  def action_html_direct
    context = build_context("GET", "/bench/multi")
    HtmlController.new(context).direct
    context.bench_finalize_response!
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

  def action_json_respond_with_no_accept
    context = build_context("GET", "/bench/json")
    JsonController.new(context).negotiated
    context.bench_finalize_response!
  end

  def action_multi_respond_with_html_default
    context = build_context("GET", "/bench/multi")
    MultiFormatController.new(context).negotiated
    context.bench_finalize_response!
  end

  def action_multi_respond_with_html_accept
    context = build_context("GET", "/bench/multi", HTML_ACCEPT)
    MultiFormatController.new(context).negotiated
    context.bench_finalize_response!
  end

  def action_multi_respond_with_json_accept
    context = build_context("GET", "/bench/multi", JSON_ACCEPT)
    MultiFormatController.new(context).negotiated
    context.bench_finalize_response!
  end

  def action_multi_respond_with_json_accept_runtime
    context = build_context("GET", "/bench/multi", JSON_ACCEPT)
    MultiFormatController.new(context).negotiated_runtime
    context.bench_finalize_response!
  end

  def action_multi_respond_with_json_wildcard
    context = build_context("GET", "/bench/multi", JSON_WILDCARD_ACCEPT)
    MultiFormatController.new(context).negotiated
    context.bench_finalize_response!
  end

  def action_multi_respond_with_path_json
    context = build_context("GET", "/bench/multi.json")
    MultiFormatController.new(context).negotiated
    context.bench_finalize_response!
  end

  def action_heavy_respond_with_json_accept
    context = build_context("GET", "/bench/heavy", JSON_ACCEPT)
    MultiFormatController.new(context).heavy_negotiated
    context.bench_finalize_response!
  end

  def action_heavy_respond_with_json_accept_runtime
    context = build_context("GET", "/bench/heavy", JSON_ACCEPT)
    MultiFormatController.new(context).heavy_negotiated_runtime
    context.bench_finalize_response!
  end

  def action_heavy_respond_with_html_accept
    context = build_context("GET", "/bench/heavy", HTML_ACCEPT)
    MultiFormatController.new(context).heavy_negotiated
    context.bench_finalize_response!
  end

  def action_heavy_respond_with_html_accept_runtime
    context = build_context("GET", "/bench/heavy", HTML_ACCEPT)
    MultiFormatController.new(context).heavy_negotiated_runtime
    context.bench_finalize_response!
  end

  def action_schema_named_tuple_respond_with
    context = build_context("GET", "/bench/schema-json")
    SchemaJsonController.new(context).named_tuple
    context.bench_finalize_response!
  end

  def dispatch_json(pipeline : Amber::Pipe::Pipeline)
    context = build_context("GET", "/bench/json", JSON_ACCEPT)
    pipeline.call(context)
  end

  def raw_query_lookup
    request = HTTP::Request.new("GET", QUERY_RESOURCE)
    query = request.query_params
    consume(query["page"].bytesize + query["sort"].bytesize + query["filter"].bytesize)
  end

  def params_lookup_query
    context = build_context("GET", QUERY_RESOURCE)
    params = context.params
    consume(params["page"].bytesize + params["sort"].bytesize + params["filter"].bytesize)
  end

  def dispatch_route_query_params(pipeline : Amber::Pipe::Pipeline)
    context = build_context("GET", "/bench/users/42?page=10&sort=asc&filter=active")
    pipeline.call(context)
  end

  def raw_json_body_parse
    parsed = JSON.parse(JSON_BODY_PAYLOAD).as_h
    consume(parsed["id"].to_s.bytesize + parsed["name"].to_s.bytesize + parsed["active"].to_s.bytesize)
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

  parser.on("--scenario=NAME", "Scenario: raw_plaintext, action_plaintext, raw_json, action_json_direct, action_json_direct_no_accept, action_html_direct, action_query_params, action_query_raw_params, action_query_validated_params, action_query_compiled_validated_params, action_query_mixed_validated_params, action_query_hybrid_validated_params, action_query_predicate_only_validated_params, action_query_predicate_only_compiled_validated_params, action_json_respond_with, action_json_respond_with_no_accept, action_multi_respond_with_html_default, action_multi_respond_with_html_accept, action_multi_respond_with_json_accept, action_multi_respond_with_json_accept_runtime, action_multi_respond_with_json_wildcard, action_multi_respond_with_path_json, action_heavy_respond_with_json_accept, action_heavy_respond_with_json_accept_runtime, action_heavy_respond_with_html_accept, action_heavy_respond_with_html_accept_runtime, action_schema_named_tuple_respond_with, dispatch_json, raw_query_lookup, params_lookup_query, dispatch_route_query_params, raw_json_body_parse, dispatch_json_body, action_json_body_raw_params, action_json_body_validated_params, action_json_body_compiled_validated_params, action_json_body_mixed_validated_params, action_json_body_hybrid_validated_params, params_lookup_json") do |value|
    scenario = value
  end

  parser.on("--duration=SECONDS", "Wall-clock run duration (default: #{duration_seconds})") do |value|
    duration_seconds = value.to_f
  end
end

AmberFrameworkPerfProfile.install_routes
pipeline = AmberFrameworkPerfProfile.build_pipeline

scenario_proc = case scenario
                when "raw_plaintext"
                  -> { AmberFrameworkPerfProfile.raw_plaintext }
                when "action_plaintext"
                  -> { AmberFrameworkPerfProfile.action_plaintext }
                when "raw_json"
                  -> { AmberFrameworkPerfProfile.raw_json }
                when "action_json_direct"
                  -> { AmberFrameworkPerfProfile.action_json_direct }
                when "action_json_direct_no_accept"
                  -> { AmberFrameworkPerfProfile.action_json_direct_no_accept }
                when "action_html_direct"
                  -> { AmberFrameworkPerfProfile.action_html_direct }
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
                when "action_json_respond_with_no_accept"
                  -> { AmberFrameworkPerfProfile.action_json_respond_with_no_accept }
                when "action_multi_respond_with_html_default"
                  -> { AmberFrameworkPerfProfile.action_multi_respond_with_html_default }
                when "action_multi_respond_with_html_accept"
                  -> { AmberFrameworkPerfProfile.action_multi_respond_with_html_accept }
                when "action_multi_respond_with_json_accept"
                  -> { AmberFrameworkPerfProfile.action_multi_respond_with_json_accept }
                when "action_multi_respond_with_json_accept_runtime"
                  -> { AmberFrameworkPerfProfile.action_multi_respond_with_json_accept_runtime }
                when "action_multi_respond_with_json_wildcard"
                  -> { AmberFrameworkPerfProfile.action_multi_respond_with_json_wildcard }
                when "action_multi_respond_with_path_json"
                  -> { AmberFrameworkPerfProfile.action_multi_respond_with_path_json }
                when "action_heavy_respond_with_json_accept"
                  -> { AmberFrameworkPerfProfile.action_heavy_respond_with_json_accept }
                when "action_heavy_respond_with_json_accept_runtime"
                  -> { AmberFrameworkPerfProfile.action_heavy_respond_with_json_accept_runtime }
                when "action_heavy_respond_with_html_accept"
                  -> { AmberFrameworkPerfProfile.action_heavy_respond_with_html_accept }
                when "action_heavy_respond_with_html_accept_runtime"
                  -> { AmberFrameworkPerfProfile.action_heavy_respond_with_html_accept_runtime }
                when "action_schema_named_tuple_respond_with"
                  -> { AmberFrameworkPerfProfile.action_schema_named_tuple_respond_with }
                when "dispatch_json"
                  -> { AmberFrameworkPerfProfile.dispatch_json(pipeline) }
                when "raw_query_lookup"
                  -> { AmberFrameworkPerfProfile.raw_query_lookup }
                when "params_lookup_query"
                  -> { AmberFrameworkPerfProfile.params_lookup_query }
                when "dispatch_route_query_params"
                  -> { AmberFrameworkPerfProfile.dispatch_route_query_params(pipeline) }
                when "raw_json_body_parse"
                  -> { AmberFrameworkPerfProfile.raw_json_body_parse }
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
