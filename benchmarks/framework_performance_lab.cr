require "benchmark"
require "json"
require "option_parser"
require "../src/amber"

record ScenarioConfig, key : String, label : String
record ComparisonConfig, key : String, label : String, base_key : String, candidate_key : String

module AmberFrameworkPerfLab
  extend self

  CONTENT_JSON = Amber::Controller::Helpers::Responders::Content::TYPE[:json]
  CONTENT_TEXT = Amber::Controller::Helpers::Responders::Content::TYPE[:text]
  JSON_ACCEPT  = HTTP::Headers{"Accept" => "application/json"}
  JSON_HEADERS = HTTP::Headers{
    "Accept"       => "application/json",
    "Content-Type" => "application/json",
  }

  PLAIN_TEXT_RESPONSE = "ok"
  JSON_RESPONSE_HASH  = {
    "status"    => "ok",
    "framework" => "amber",
    "version"   => "2",
  }
  JSON_RESPONSE_BODY        = JSON_RESPONSE_HASH.to_json
  QUERY_RESOURCE            = "/bench/query?page=10&sort=asc&filter=active"
  ROUTE_QUERY_PATH          = "/bench/users/42?page=10&sort=asc&filter=active"
  JSON_BODY_RESOURCE        = "/bench/json-body"
  JSON_BODY_PAYLOAD         = %({"id":42,"name":"amber","active":true})
  QUERY_HYBRID_FILTER_FIELD = "filter"
  QUERY_HYBRID_FILTER_MSG   = "Filter must be active"
  JSON_HYBRID_NAME_FIELD    = "name"
  JSON_HYBRID_NAME_MSG      = "Name must be amber"

  SCENARIOS = [
    ScenarioConfig.new("raw_plaintext", "Raw Crystal plaintext"),
    ScenarioConfig.new("amber_action_plaintext", "Amber controller plaintext"),
    ScenarioConfig.new("amber_dispatch_plaintext", "Amber dispatch plaintext"),
    ScenarioConfig.new("amber_dispatch_plaintext_3pipes", "Amber dispatch plaintext with 3 no-op pipes"),
    ScenarioConfig.new("raw_json", "Raw Crystal JSON"),
    ScenarioConfig.new("amber_action_json_direct", "Amber controller JSON direct"),
    ScenarioConfig.new("amber_action_json_respond_with", "Amber controller JSON respond_with"),
    ScenarioConfig.new("amber_dispatch_json", "Amber dispatch JSON"),
    ScenarioConfig.new("raw_query_lookup", "Raw query lookup"),
    ScenarioConfig.new("amber_params_lookup_query", "Amber params query lookup"),
    ScenarioConfig.new("amber_action_query_raw_params", "Amber controller raw query params"),
    ScenarioConfig.new("amber_action_query_params", "Amber controller query params"),
    ScenarioConfig.new("amber_action_query_validated_params", "Amber controller validated query params"),
    ScenarioConfig.new("amber_action_query_compiled_validated_params", "Amber controller compiled validated query params"),
    ScenarioConfig.new("amber_action_query_mixed_validated_params", "Amber controller mixed validated query params"),
    ScenarioConfig.new("amber_action_query_hybrid_validated_params", "Amber controller hybrid compiled query params"),
    ScenarioConfig.new("amber_dispatch_route_query_params", "Amber dispatch route+query params"),
    ScenarioConfig.new("raw_json_body_parse", "Raw JSON body parse"),
    ScenarioConfig.new("amber_params_lookup_json", "Amber params JSON body lookup"),
    ScenarioConfig.new("amber_action_json_body_raw_params", "Amber controller raw JSON body params"),
    ScenarioConfig.new("amber_action_json_body_validated_params", "Amber controller validated JSON body params"),
    ScenarioConfig.new("amber_action_json_body_compiled_validated_params", "Amber controller compiled validated JSON body params"),
    ScenarioConfig.new("amber_action_json_body_mixed_validated_params", "Amber controller mixed validated JSON body params"),
    ScenarioConfig.new("amber_action_json_body_hybrid_validated_params", "Amber controller hybrid compiled JSON body params"),
    ScenarioConfig.new("amber_dispatch_json_body", "Amber dispatch JSON body"),
  ]

  COMPARISONS = [
    ComparisonConfig.new("plaintext_controller_vs_raw", "Controller plaintext vs raw", "raw_plaintext", "amber_action_plaintext"),
    ComparisonConfig.new("plaintext_dispatch_vs_raw", "Dispatch plaintext vs raw", "raw_plaintext", "amber_dispatch_plaintext"),
    ComparisonConfig.new("plaintext_3pipes_vs_dispatch", "3 no-op pipes vs plain dispatch", "amber_dispatch_plaintext", "amber_dispatch_plaintext_3pipes"),
    ComparisonConfig.new("json_direct_vs_raw", "Controller direct JSON vs raw", "raw_json", "amber_action_json_direct"),
    ComparisonConfig.new("json_respond_with_vs_direct", "respond_with JSON vs direct JSON", "amber_action_json_direct", "amber_action_json_respond_with"),
    ComparisonConfig.new("json_dispatch_vs_raw", "Dispatch JSON vs raw", "raw_json", "amber_dispatch_json"),
    ComparisonConfig.new("query_params_vs_raw", "Amber query lookup vs raw", "raw_query_lookup", "amber_params_lookup_query"),
    ComparisonConfig.new("query_action_wrapper_vs_raw_action", "Controller wrapped query params vs raw params", "amber_action_query_raw_params", "amber_action_query_params"),
    ComparisonConfig.new("query_action_validated_vs_raw_action", "Controller validated query params vs raw params", "amber_action_query_raw_params", "amber_action_query_validated_params"),
    ComparisonConfig.new("query_action_compiled_vs_validated", "Controller compiled validated query params vs validated params", "amber_action_query_validated_params", "amber_action_query_compiled_validated_params"),
    ComparisonConfig.new("query_action_hybrid_vs_mixed", "Controller hybrid compiled query params vs mixed validated params", "amber_action_query_mixed_validated_params", "amber_action_query_hybrid_validated_params"),
    ComparisonConfig.new("query_action_vs_params", "Controller query params vs params lookup", "amber_params_lookup_query", "amber_action_query_params"),
    ComparisonConfig.new("route_query_dispatch_vs_action", "Dispatch route+query params vs controller query params", "amber_action_query_params", "amber_dispatch_route_query_params"),
    ComparisonConfig.new("json_params_vs_raw_parse", "Amber JSON body params vs raw JSON parse", "raw_json_body_parse", "amber_params_lookup_json"),
    ComparisonConfig.new("json_body_action_validated_vs_raw_action", "Controller validated JSON body params vs raw params", "amber_action_json_body_raw_params", "amber_action_json_body_validated_params"),
    ComparisonConfig.new("json_body_action_compiled_vs_validated", "Controller compiled validated JSON body params vs validated params", "amber_action_json_body_validated_params", "amber_action_json_body_compiled_validated_params"),
    ComparisonConfig.new("json_body_action_hybrid_vs_mixed", "Controller hybrid compiled JSON body params vs mixed validated params", "amber_action_json_body_mixed_validated_params", "amber_action_json_body_hybrid_validated_params"),
    ComparisonConfig.new("json_dispatch_vs_params", "Dispatch JSON body vs params lookup", "amber_params_lookup_json", "amber_dispatch_json_body"),
  ]

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
      set_response(AmberFrameworkPerfLab::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfLab::CONTENT_TEXT)
    end
  end

  class JsonController < Amber::Controller::Base
    def direct
      set_response(AmberFrameworkPerfLab::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfLab::CONTENT_JSON)
    end

    def negotiated
      respond_with do
        json(AmberFrameworkPerfLab::JSON_RESPONSE_BODY)
      end
    end
  end

  class QueryParamsController < Amber::Controller::Base
    def raw_index
      current_params = raw_params
      AmberFrameworkPerfLab.consume(current_params["page"].bytesize + current_params["sort"].bytesize + current_params["filter"].bytesize)
      set_response(AmberFrameworkPerfLab::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfLab::CONTENT_TEXT)
    end

    def index
      AmberFrameworkPerfLab.consume(params["page"].bytesize + params["sort"].bytesize + params["filter"].bytesize)
      set_response(AmberFrameworkPerfLab::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfLab::CONTENT_TEXT)
    end

    def validated_index
      validated_params = params.validation do
        required(:page)
        required(:sort)
        required(:filter)
      end.validate!
      AmberFrameworkPerfLab.consume(
        validated_params["page"].not_nil!.bytesize +
        validated_params["sort"].not_nil!.bytesize +
        validated_params["filter"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfLab::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfLab::CONTENT_TEXT)
    end

    def compiled_validated_index
      validated_params = legacy_params.validation(AmberFrameworkPerfLab::QUERY_VALIDATION).validate!
      AmberFrameworkPerfLab.consume(
        validated_params["page"].not_nil!.bytesize +
        validated_params["sort"].not_nil!.bytesize +
        validated_params["filter"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfLab::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfLab::CONTENT_TEXT)
    end

    def mixed_validated_index
      validated_params = params.validation do
        required(:page)
        required(:sort)
        required(AmberFrameworkPerfLab::QUERY_HYBRID_FILTER_FIELD, AmberFrameworkPerfLab::QUERY_HYBRID_FILTER_MSG) { |value| value == "active" }
      end.validate!
      AmberFrameworkPerfLab.consume(
        validated_params["page"].not_nil!.bytesize +
        validated_params["sort"].not_nil!.bytesize +
        validated_params["filter"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfLab::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfLab::CONTENT_TEXT)
    end

    def hybrid_validated_index
      validated_params = legacy_params.validation(AmberFrameworkPerfLab::QUERY_HYBRID_VALIDATION).validate!
      AmberFrameworkPerfLab.consume(
        validated_params["page"].not_nil!.bytesize +
        validated_params["sort"].not_nil!.bytesize +
        validated_params["filter"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfLab::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfLab::CONTENT_TEXT)
    end
  end

  class RouteQueryController < Amber::Controller::Base
    def show
      AmberFrameworkPerfLab.consume(params["id"].bytesize + params["page"].bytesize + params["sort"].bytesize + params["filter"].bytesize)
      set_response(AmberFrameworkPerfLab::PLAIN_TEXT_RESPONSE, 200, AmberFrameworkPerfLab::CONTENT_TEXT)
    end
  end

  class JsonBodyController < Amber::Controller::Base
    def raw_create
      current_params = raw_params
      AmberFrameworkPerfLab.consume(current_params["id"].bytesize + current_params["name"].bytesize + current_params["active"].bytesize)
      set_response(AmberFrameworkPerfLab::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfLab::CONTENT_JSON)
    end

    def create
      AmberFrameworkPerfLab.consume(params["id"].bytesize + params["name"].bytesize + params["active"].bytesize)
      set_response(AmberFrameworkPerfLab::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfLab::CONTENT_JSON)
    end

    def validated_create
      validated_params = params.validation do
        required(:id)
        required(:name)
        required(:active)
      end.validate!
      AmberFrameworkPerfLab.consume(
        validated_params["id"].not_nil!.bytesize +
        validated_params["name"].not_nil!.bytesize +
        validated_params["active"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfLab::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfLab::CONTENT_JSON)
    end

    def compiled_validated_create
      validated_params = legacy_params.validation(AmberFrameworkPerfLab::JSON_BODY_VALIDATION).validate!
      AmberFrameworkPerfLab.consume(
        validated_params["id"].not_nil!.bytesize +
        validated_params["name"].not_nil!.bytesize +
        validated_params["active"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfLab::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfLab::CONTENT_JSON)
    end

    def mixed_validated_create
      validated_params = params.validation do
        required(:id)
        required(AmberFrameworkPerfLab::JSON_HYBRID_NAME_FIELD, AmberFrameworkPerfLab::JSON_HYBRID_NAME_MSG) { |value| value == "amber" }
        required(:active)
      end.validate!
      AmberFrameworkPerfLab.consume(
        validated_params["id"].not_nil!.bytesize +
        validated_params["name"].not_nil!.bytesize +
        validated_params["active"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfLab::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfLab::CONTENT_JSON)
    end

    def hybrid_validated_create
      validated_params = legacy_params.validation(AmberFrameworkPerfLab::JSON_BODY_HYBRID_VALIDATION).validate!
      AmberFrameworkPerfLab.consume(
        validated_params["id"].not_nil!.bytesize +
        validated_params["name"].not_nil!.bytesize +
        validated_params["active"].not_nil!.bytesize
      )
      set_response(AmberFrameworkPerfLab::JSON_RESPONSE_BODY, 200, AmberFrameworkPerfLab::CONTENT_JSON)
    end
  end

  class NoopPipe < Amber::Pipe::Base
  end

  def definition_metadata_entry(key : String, label : String, definition, scenario_key : String? = nil) : JSON::Any
    payload = {
      "key"   => JSON::Any.new(key),
      "label" => JSON::Any.new(label),
    } of String => JSON::Any

    if scenario_key
      payload["scenario_key"] = JSON::Any.new(scenario_key)
    end

    metadata_available = false

    if definition.responds_to?(:total_rule_count)
      payload["total_rule_count"] = JSON::Any.new(definition.total_rule_count.to_i64)
      metadata_available = true
    end

    if definition.responds_to?(:direct_rule_count)
      payload["direct_rule_count"] = JSON::Any.new(definition.direct_rule_count.to_i64)
      metadata_available = true
    end

    if definition.responds_to?(:fallback_rule_count)
      payload["fallback_rule_count"] = JSON::Any.new(definition.fallback_rule_count.to_i64)
      metadata_available = true
    end

    if definition.responds_to?(:hybrid?)
      payload["hybrid"] = JSON::Any.new(definition.hybrid?)
      metadata_available = true
    end

    payload["metadata_available"] = JSON::Any.new(metadata_available)
    JSON::Any.new(payload)
  end

  def validation_definition_metadata : Array(JSON::Any)
    [
      definition_metadata_entry(
        "query_compiled_simple",
        "Simple compiled query params",
        QUERY_VALIDATION,
        scenario_key: "amber_action_query_compiled_validated_params"
      ),
      definition_metadata_entry(
        "query_compiled_hybrid",
        "Hybrid compiled query params",
        QUERY_HYBRID_VALIDATION,
        scenario_key: "amber_action_query_hybrid_validated_params"
      ),
      definition_metadata_entry(
        "query_compiled_predicate_only",
        "Predicate-only compiled query params",
        QUERY_PREDICATE_ONLY_VALIDATION
      ),
      definition_metadata_entry(
        "json_body_compiled_simple",
        "Simple compiled JSON body params",
        JSON_BODY_VALIDATION,
        scenario_key: "amber_action_json_body_compiled_validated_params"
      ),
      definition_metadata_entry(
        "json_body_compiled_hybrid",
        "Hybrid compiled JSON body params",
        JSON_BODY_HYBRID_VALIDATION,
        scenario_key: "amber_action_json_body_hybrid_validated_params"
      ),
    ]
  end

  def consume(value : Int32)
    @@sink = value
  end

  def install_routes
    router = Amber::Server.router
    routes = [
      Amber::Route.new("GET", "/bench/plaintext", ->(context : HTTP::Server::Context) { PlaintextController.new(context).index }, :index, :web, controller: "AmberFrameworkPerfLab::PlaintextController"),
      Amber::Route.new("GET", "/bench/json", ->(context : HTTP::Server::Context) { JsonController.new(context).negotiated }, :negotiated, :web, controller: "AmberFrameworkPerfLab::JsonController"),
      Amber::Route.new("GET", "/bench/users/:id", ->(context : HTTP::Server::Context) { RouteQueryController.new(context).show }, :show, :web, controller: "AmberFrameworkPerfLab::RouteQueryController"),
      Amber::Route.new("POST", "/bench/json-body", ->(context : HTTP::Server::Context) { JsonBodyController.new(context).create }, :create, :web, controller: "AmberFrameworkPerfLab::JsonBodyController"),
    ]

    routes.each { |route| router.add(route) }
  end

  def build_pipeline(pipe_count : Int32 = 0) : Amber::Pipe::Pipeline
    pipeline = Amber::Pipe::Pipeline.new
    pipe_count.times { pipeline.plug(NoopPipe.new) }
    pipeline.prepare_pipelines
    pipeline
  end

  def build_context(method : String, resource : String, headers : HTTP::Headers = HTTP::Headers.new, body = "") : {HTTP::Server::Context, IO::Memory}
    request = HTTP::Request.new(method, resource, headers, body)
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    {HTTP::Server::Context.new(request, response), io}
  end

  def raw_plaintext
    tuple = build_context("GET", "/raw/plaintext")
    context = tuple[0]
    context.response.status_code = 200
    context.response.content_type = CONTENT_TEXT
    context.response.print(PLAIN_TEXT_RESPONSE)
  end

  def amber_action_plaintext
    tuple = build_context("GET", "/bench/plaintext")
    context = tuple[0]
    PlaintextController.new(context).index
    context.bench_finalize_response!
  end

  def amber_dispatch_plaintext(pipeline : Amber::Pipe::Pipeline)
    tuple = build_context("GET", "/bench/plaintext")
    context = tuple[0]
    pipeline.call(context)
  end

  def raw_json
    tuple = build_context("GET", "/raw/json", JSON_ACCEPT)
    context = tuple[0]
    context.response.status_code = 200
    context.response.content_type = CONTENT_JSON
    context.response.print(JSON_RESPONSE_BODY)
  end

  def amber_action_json_direct
    tuple = build_context("GET", "/bench/json", JSON_ACCEPT)
    context = tuple[0]
    JsonController.new(context).direct
    context.bench_finalize_response!
  end

  def amber_action_json_respond_with
    tuple = build_context("GET", "/bench/json", JSON_ACCEPT)
    context = tuple[0]
    JsonController.new(context).negotiated
    context.bench_finalize_response!
  end

  def amber_dispatch_json(pipeline : Amber::Pipe::Pipeline)
    tuple = build_context("GET", "/bench/json", JSON_ACCEPT)
    context = tuple[0]
    pipeline.call(context)
  end

  def raw_query_lookup
    request = HTTP::Request.new("GET", QUERY_RESOURCE)
    query = request.query_params
    consume(query["page"].bytesize + query["sort"].bytesize + query["filter"].bytesize)
  end

  def amber_params_lookup_query
    tuple = build_context("GET", QUERY_RESOURCE)
    context = tuple[0]
    params = context.params
    consume(params["page"].bytesize + params["sort"].bytesize + params["filter"].bytesize)
  end

  def amber_action_query_params
    tuple = build_context("GET", QUERY_RESOURCE)
    context = tuple[0]
    QueryParamsController.new(context).index
    context.bench_finalize_response!
  end

  def amber_action_query_raw_params
    tuple = build_context("GET", QUERY_RESOURCE)
    context = tuple[0]
    QueryParamsController.new(context).raw_index
    context.bench_finalize_response!
  end

  def amber_action_query_validated_params
    tuple = build_context("GET", QUERY_RESOURCE)
    context = tuple[0]
    QueryParamsController.new(context).validated_index
    context.bench_finalize_response!
  end

  def amber_action_query_compiled_validated_params
    tuple = build_context("GET", QUERY_RESOURCE)
    context = tuple[0]
    QueryParamsController.new(context).compiled_validated_index
    context.bench_finalize_response!
  end

  def amber_action_query_mixed_validated_params
    tuple = build_context("GET", QUERY_RESOURCE)
    context = tuple[0]
    QueryParamsController.new(context).mixed_validated_index
    context.bench_finalize_response!
  end

  def amber_action_query_hybrid_validated_params
    tuple = build_context("GET", QUERY_RESOURCE)
    context = tuple[0]
    QueryParamsController.new(context).hybrid_validated_index
    context.bench_finalize_response!
  end

  def amber_dispatch_route_query_params(pipeline : Amber::Pipe::Pipeline)
    tuple = build_context("GET", ROUTE_QUERY_PATH)
    context = tuple[0]
    pipeline.call(context)
  end

  def raw_json_body_parse
    parsed = JSON.parse(JSON_BODY_PAYLOAD).as_h
    consume(parsed["id"].to_s.bytesize + parsed["name"].to_s.bytesize + parsed["active"].to_s.bytesize)
  end

  def amber_params_lookup_json
    tuple = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    context = tuple[0]
    params = context.params
    consume(params["id"].bytesize + params["name"].bytesize + params["active"].bytesize)
  end

  def amber_action_json_body_raw_params
    tuple = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    context = tuple[0]
    JsonBodyController.new(context).raw_create
    context.bench_finalize_response!
  end

  def amber_action_json_body_validated_params
    tuple = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    context = tuple[0]
    JsonBodyController.new(context).validated_create
    context.bench_finalize_response!
  end

  def amber_action_json_body_compiled_validated_params
    tuple = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    context = tuple[0]
    JsonBodyController.new(context).compiled_validated_create
    context.bench_finalize_response!
  end

  def amber_action_json_body_mixed_validated_params
    tuple = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    context = tuple[0]
    JsonBodyController.new(context).mixed_validated_create
    context.bench_finalize_response!
  end

  def amber_action_json_body_hybrid_validated_params
    tuple = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    context = tuple[0]
    JsonBodyController.new(context).hybrid_validated_create
    context.bench_finalize_response!
  end

  def amber_dispatch_json_body(pipeline : Amber::Pipe::Pipeline)
    tuple = build_context("POST", JSON_BODY_RESOURCE, JSON_HEADERS, JSON_BODY_PAYLOAD)
    context = tuple[0]
    pipeline.call(context)
  end
end

warmup_seconds = 2.0
calculation_seconds = 5.0
output_path = "benchmarks/results/framework_performance_lab_latest.json"
compiler_label = ENV["AMBER_BENCH_COMPILER"]? || "unknown"

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal run benchmarks/framework_performance_lab.cr -- [options]"

  parser.on("--warmup=SECONDS", "Warmup seconds per measurement (default: #{warmup_seconds})") do |value|
    warmup_seconds = value.to_f
  end

  parser.on("--calc=SECONDS", "Calculation seconds per measurement (default: #{calculation_seconds})") do |value|
    calculation_seconds = value.to_f
  end

  parser.on("--output=PATH", "Where to write the JSON results") do |value|
    output_path = value
  end
end

AmberFrameworkPerfLab.install_routes

dispatch_pipeline = AmberFrameworkPerfLab.build_pipeline
dispatch_pipeline_with_pipes = AmberFrameworkPerfLab.build_pipeline(3)

scenario_actions = {
  "raw_plaintext"                                    => -> { AmberFrameworkPerfLab.raw_plaintext },
  "amber_action_plaintext"                           => -> { AmberFrameworkPerfLab.amber_action_plaintext },
  "amber_dispatch_plaintext"                         => -> { AmberFrameworkPerfLab.amber_dispatch_plaintext(dispatch_pipeline) },
  "amber_dispatch_plaintext_3pipes"                  => -> { AmberFrameworkPerfLab.amber_dispatch_plaintext(dispatch_pipeline_with_pipes) },
  "raw_json"                                         => -> { AmberFrameworkPerfLab.raw_json },
  "amber_action_json_direct"                         => -> { AmberFrameworkPerfLab.amber_action_json_direct },
  "amber_action_json_respond_with"                   => -> { AmberFrameworkPerfLab.amber_action_json_respond_with },
  "amber_dispatch_json"                              => -> { AmberFrameworkPerfLab.amber_dispatch_json(dispatch_pipeline) },
  "raw_query_lookup"                                 => -> { AmberFrameworkPerfLab.raw_query_lookup },
  "amber_params_lookup_query"                        => -> { AmberFrameworkPerfLab.amber_params_lookup_query },
  "amber_action_query_raw_params"                    => -> { AmberFrameworkPerfLab.amber_action_query_raw_params },
  "amber_action_query_params"                        => -> { AmberFrameworkPerfLab.amber_action_query_params },
  "amber_action_query_validated_params"              => -> { AmberFrameworkPerfLab.amber_action_query_validated_params },
  "amber_action_query_compiled_validated_params"     => -> { AmberFrameworkPerfLab.amber_action_query_compiled_validated_params },
  "amber_action_query_mixed_validated_params"        => -> { AmberFrameworkPerfLab.amber_action_query_mixed_validated_params },
  "amber_action_query_hybrid_validated_params"       => -> { AmberFrameworkPerfLab.amber_action_query_hybrid_validated_params },
  "amber_dispatch_route_query_params"                => -> { AmberFrameworkPerfLab.amber_dispatch_route_query_params(dispatch_pipeline) },
  "raw_json_body_parse"                              => -> { AmberFrameworkPerfLab.raw_json_body_parse },
  "amber_params_lookup_json"                         => -> { AmberFrameworkPerfLab.amber_params_lookup_json },
  "amber_action_json_body_raw_params"                => -> { AmberFrameworkPerfLab.amber_action_json_body_raw_params },
  "amber_action_json_body_validated_params"          => -> { AmberFrameworkPerfLab.amber_action_json_body_validated_params },
  "amber_action_json_body_compiled_validated_params" => -> { AmberFrameworkPerfLab.amber_action_json_body_compiled_validated_params },
  "amber_action_json_body_mixed_validated_params"    => -> { AmberFrameworkPerfLab.amber_action_json_body_mixed_validated_params },
  "amber_action_json_body_hybrid_validated_params"   => -> { AmberFrameworkPerfLab.amber_action_json_body_hybrid_validated_params },
  "amber_dispatch_json_body"                         => -> { AmberFrameworkPerfLab.amber_dispatch_json_body(dispatch_pipeline) },
} of String => Proc(Nil)

results = [] of Hash(String, Float64 | String)

puts "Amber Framework Performance Lab"
puts "Crystal #{Crystal::VERSION}"
puts "Compiler: #{compiler_label}"
puts "Warmup: #{warmup_seconds}s | Calculation: #{calculation_seconds}s"

AmberFrameworkPerfLab::SCENARIOS.each do |scenario|
  action = scenario_actions[scenario.key]
  memory = Benchmark.memory { action.call }
  job = Benchmark.ips(warmup: warmup_seconds.seconds, calculation: calculation_seconds.seconds) do |x|
    x.report(scenario.key) { action.call }
  end
  ips = job.items.first.mean

  puts "#{scenario.key.ljust(32)} | #{ips.round(0).to_s.rjust(10)} IPS | #{memory.to_s.rjust(8)} B"

  results << {
    "key"          => scenario.key,
    "label"        => scenario.label,
    "ips"          => ips,
    "memory_bytes" => memory.to_f64,
  }
end

result_index = results.index_by { |row| row["key"].as(String) }

comparisons = AmberFrameworkPerfLab::COMPARISONS.map do |comparison|
  base = result_index[comparison.base_key]
  candidate = result_index[comparison.candidate_key]

  base_ips = base["ips"].as(Float64)
  candidate_ips = candidate["ips"].as(Float64)
  base_memory = base["memory_bytes"].as(Float64)
  candidate_memory = candidate["memory_bytes"].as(Float64)
  memory_comparable = base_memory > 0.0

  {
    "key"               => comparison.key,
    "label"             => comparison.label,
    "base_key"          => comparison.base_key,
    "candidate_key"     => comparison.candidate_key,
    "ips_ratio"         => candidate_ips / base_ips,
    "ips_delta_pct"     => ((candidate_ips / base_ips) - 1.0) * 100.0,
    "slower_factor"     => base_ips / candidate_ips,
    "memory_comparable" => memory_comparable ? "yes" : "no",
    "memory_ratio"      => memory_comparable ? candidate_memory / base_memory : 0.0,
    "memory_delta_pct"  => memory_comparable ? ((candidate_memory / base_memory) - 1.0) * 100.0 : 0.0,
  }
end.sort_by { |row| row["ips_ratio"].as(Float64) }

payload = {
  "metadata" => {
    "compiler"            => compiler_label,
    "crystal_version"     => Crystal::VERSION,
    "generated_at_utc"    => Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
    "warmup_seconds"      => warmup_seconds,
    "calculation_seconds" => calculation_seconds,
    "validation_definitions" => AmberFrameworkPerfLab.validation_definition_metadata,
  },
  "results" => results,
  "summary" => {
    "comparisons" => comparisons,
  },
}

timestamped_output = output_path.sub(/\.json$/, "_#{Time.local.to_s("%Y%m%d_%H%M%S")}.json")
File.write(output_path, payload.to_pretty_json)
File.write(timestamped_output, payload.to_pretty_json)

puts
puts "Priority order (lowest IPS ratio first):"
comparisons.each do |comparison|
  label = comparison["label"].as(String)
  ratio = comparison["ips_ratio"].as(Float64)
  delta = comparison["ips_delta_pct"].as(Float64)
  puts "- #{label}: ratio=#{ratio.round(3)} delta=#{delta.round(1)}%"
end

puts
puts "Wrote #{output_path}"
puts "Wrote #{timestamped_output}"
