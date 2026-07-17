module Amber::Benchmarks::RouterRevalidation
  STATIC_ACTIONS   = %w(index new search stats export archive)
  VARIABLE_ACTIONS = %w(show edit update comments history permissions)

  INTEGER_CONSTRAINT = /\A[0-9]+\z/
  UUID_CONSTRAINT    = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  ULID_CONSTRAINT    = /\A[0-9A-HJKMNP-TV-Z]{26}\z/

  IDENTIFIER_STYLES = [:integer, :uuid, :ulid, :slug]
  TRAFFIC_PROFILES  = [
    :mixed,
    :static,
    :rest_integer,
    :rest_uuid,
    :rest_ulid,
    :rest_slug,
    :dynamic_uuid,
    :nested_uuid,
    :constrained_integer,
    :constrained_uuid,
    :constrained_ulid,
    :glob,
    :notfound,
  ]

  struct RouteDefinition
    getter resource : String
    getter payload : Int32
    getter kind : Symbol
    getter constraints : Hash(String, Regex)
    getter constraint_style : Symbol?

    def initialize(
      @resource,
      @payload,
      @kind,
      @constraints = {} of String => Regex,
      @constraint_style = nil,
    )
    end

    def trail : String
      "get#{resource}"
    end

    def matching_resource(seed : Int32, identifier_style : Symbol? = nil) : String
      style = identifier_style || constraint_style || :integer
      resource
        .gsub(":child_id", RouterRevalidation.identifier(style, seed + 1_000_000))
        .gsub(":id", RouterRevalidation.identifier(style, seed))
        .gsub("*path", "images/#{seed}/thumbnail.webp")
    end
  end

  struct TrafficRequest
    getter path : String
    getter resource : String
    getter kind : Symbol
    getter identifier_style : Symbol?

    def initialize(@path, @kind, @identifier_style = nil)
      @resource = path.byte_slice(3, path.bytesize - 3)
    end
  end

  def self.identifier(style : Symbol, seed : Int32) : String
    case style
    when :integer
      (10_000_000 + seed).to_s
    when :uuid
      suffix = seed.to_i64.to_s(16).rjust(12, '0')
      "018f1e2d-3c4b-7a69-8f01-#{suffix}"
    when :ulid
      "01J8Z3M5N7#{seed.to_i64.to_s.rjust(16, '0')}"
    when :slug
      "customer-order-#{seed}-spring-catalog"
    else
      raise ArgumentError.new("unknown identifier style: #{style}")
    end
  end

  def self.profile_description(profile : Symbol) : String
    case profile
    when :mixed               then "45% static; 25% REST ID; 15% dynamic action; 5% nested; 5% constrained; 5% glob"
    when :static              then "literal-only paths with no captured parameters"
    when :rest_integer        then "REST resource routes ending in an unconstrained decimal-looking :id"
    when :rest_uuid           then "REST resource routes ending in an unconstrained 36-byte UUID :id"
    when :rest_ulid           then "REST resource routes ending in an unconstrained 26-byte ULID :id"
    when :rest_slug           then "REST resource routes ending in an unconstrained human-readable slug :id"
    when :dynamic_uuid        then "unconstrained UUID :id followed by a literal action segment"
    when :nested_uuid         then "two unconstrained UUID parameters in one path"
    when :constrained_integer then "decimal :id checked by an anchored regular expression"
    when :constrained_uuid    then "UUID :id checked by an anchored regular expression"
    when :constrained_ulid    then "ULID :id checked by an anchored regular expression"
    when :glob                then "multi-segment wildcard capture"
    when :notfound            then "paths that do not match any registered route"
    else                           raise ArgumentError.new("unknown traffic profile: #{profile}")
    end
  end

  def self.profile_from_string(name : String) : Symbol
    case name
    when "mixed"               then :mixed
    when "static"              then :static
    when "rest_integer"        then :rest_integer
    when "rest_uuid"           then :rest_uuid
    when "rest_ulid"           then :rest_ulid
    when "rest_slug"           then :rest_slug
    when "dynamic_uuid"        then :dynamic_uuid
    when "nested_uuid"         then :nested_uuid
    when "constrained_integer" then :constrained_integer
    when "constrained_uuid"    then :constrained_uuid
    when "constrained_ulid"    then :constrained_ulid
    when "glob"                then :glob
    when "notfound"            then :notfound
    else                            raise ArgumentError.new("unknown traffic profile: #{name}")
    end
  end

  def self.generate_routes(count : Int32) : Array(RouteDefinition)
    raise ArgumentError.new("route count must be positive") unless count > 0

    routes = Array(RouteDefinition).new(count)
    static_count = count * 45 // 100
    restful_count = count * 25 // 100
    variable_count = count * 15 // 100
    nested_count = count * 5 // 100
    constrained_count = count * 5 // 100
    glob_count = count - static_count - restful_count - variable_count - nested_count - constrained_count
    payload = 0

    static_count.times do |index|
      resource = index % 100
      action_index = index // 100
      action = STATIC_ACTIONS[action_index % STATIC_ACTIONS.size]
      generation = action_index // STATIC_ACTIONS.size
      suffix = generation.zero? ? "" : "/generation_#{generation}"
      routes << RouteDefinition.new("/api/v#{index % 3 + 1}/resource_#{resource}/#{action}#{suffix}", payload, :static)
      payload += 1
    end

    restful_count.times do |index|
      routes << RouteDefinition.new("/api/v#{index % 3 + 1}/rest_resource_#{index}/:id", payload, :restful)
      payload += 1
    end

    variable_count.times do |index|
      resource = index % 100
      action_index = index // 100
      action = VARIABLE_ACTIONS[action_index % VARIABLE_ACTIONS.size]
      generation = action_index // VARIABLE_ACTIONS.size
      suffix = generation.zero? ? "" : "/generation_#{generation}"
      routes << RouteDefinition.new("/api/v#{index % 3 + 1}/resource_#{resource}/:id/#{action}#{suffix}", payload, :variable)
      payload += 1
    end

    nested_count.times do |index|
      routes << RouteDefinition.new("/api/v#{index % 3 + 1}/resource_#{index}/:id/children/:child_id", payload, :nested)
      payload += 1
    end

    constrained_count.times do |index|
      style = IDENTIFIER_STYLES[index % 3]
      pattern = case style
                when :integer then INTEGER_CONSTRAINT
                when :uuid    then UUID_CONSTRAINT
                when :ulid    then ULID_CONSTRAINT
                else               raise "unsupported constrained identifier: #{style}"
                end
      routes << RouteDefinition.new(
        "/api/v#{index % 3 + 1}/account_#{index}/:id/revision",
        payload,
        :constrained,
        {"id" => pattern},
        style
      )
      payload += 1
    end

    glob_count.times do |index|
      routes << RouteDefinition.new("/assets/bundle_#{index}/*path", payload, :glob)
      payload += 1
    end

    routes
  end

  def self.generate_traffic(routes : Array(RouteDefinition), size = 4096, include_misses = true) : Array(TrafficRequest)
    generate_profile_traffic(routes, :mixed, size, include_misses: include_misses)
  end

  def self.generate_profile_traffic(
    routes : Array(RouteDefinition),
    profile : Symbol,
    size = 4096,
    *,
    include_misses = false,
  ) : Array(TrafficRequest)
    raise ArgumentError.new("unknown traffic profile: #{profile}") unless TRAFFIC_PROFILES.includes?(profile)

    grouped = routes.group_by(&.kind)
    traffic = Array(TrafficRequest).new(size)

    size.times do |index|
      if profile == :notfound
        traffic << notfound_request(index)
        next
      end

      kind, style = profile_selection(profile, index, include_misses)
      if kind == :notfound
        traffic << notfound_request(index)
        next
      end

      definitions = grouped[kind]
      if kind == :constrained
        definitions = definitions.select { |definition| definition.constraint_style == style }
      end
      definition = select_definition(definitions, index)
      identifier_style = style || definition.constraint_style
      path = "get#{definition.matching_resource(index, identifier_style)}"
      traffic << TrafficRequest.new(path, kind, identifier_style)
    end

    traffic
  end

  private def self.profile_selection(profile : Symbol, index : Int32, include_misses : Bool) : {Symbol, Symbol?}
    case profile
    when :mixed
      mixed_selection(index, include_misses)
    when :static
      {:static, nil}
    when :rest_integer
      {:restful, :integer}
    when :rest_uuid
      {:restful, :uuid}
    when :rest_ulid
      {:restful, :ulid}
    when :rest_slug
      {:restful, :slug}
    when :dynamic_uuid
      {:variable, :uuid}
    when :nested_uuid
      {:nested, :uuid}
    when :constrained_integer
      {:constrained, :integer}
    when :constrained_uuid
      {:constrained, :uuid}
    when :constrained_ulid
      {:constrained, :ulid}
    when :glob
      {:glob, nil}
    else
      raise ArgumentError.new("unknown traffic profile: #{profile}")
    end
  end

  private def self.mixed_selection(index : Int32, include_misses : Bool) : {Symbol, Symbol?}
    bucket = index % 100
    if include_misses
      return {:notfound, nil} if bucket >= 98
      kind = case bucket
             when 0..43  then :static
             when 44..68 then :restful
             when 69..83 then :variable
             when 84..88 then :nested
             when 89..93 then :constrained
             else             :glob
             end
    else
      kind = case bucket
             when 0..44  then :static
             when 45..69 then :restful
             when 70..84 then :variable
             when 85..89 then :nested
             when 90..94 then :constrained
             else             :glob
             end
    end

    style = case kind
            when :restful, :variable, :nested
              IDENTIFIER_STYLES[index % IDENTIFIER_STYLES.size]
            when :constrained
              IDENTIFIER_STYLES[index % 3]
            else
              nil
            end
    {kind, style}
  end

  private def self.select_definition(definitions : Array(RouteDefinition), index : Int32) : RouteDefinition
    raise "traffic profile has no matching route definitions" if definitions.empty?

    hot_count = {definitions.size, 24}.min
    route_index = if index % 10 < 7
                    index % hot_count
                  else
                    (index.to_i64 * 131 % definitions.size).to_i
                  end
    definitions[route_index]
  end

  private def self.notfound_request(index : Int32) : TrafficRequest
    TrafficRequest.new("get/api/v9/missing_#{index % 31}/#{index}", :notfound)
  end
end
