module Amber::Benchmarks::RouterRevalidation
  STATIC_ACTIONS   = %w(index new search stats export archive)
  VARIABLE_ACTIONS = %w(show edit update comments history permissions)

  struct RouteDefinition
    getter resource : String
    getter payload : Int32
    getter kind : Symbol
    getter constraints : Hash(String, Regex)

    def initialize(@resource, @payload, @kind, @constraints = {} of String => Regex)
    end

    def trail : String
      "get#{resource}"
    end

    def matching_resource(seed : Int32) : String
      resource
        .gsub(":id", (10_000 + seed).to_s)
        .gsub(":child_id", (20_000 + seed).to_s)
        .gsub("*path", "images/#{seed}/thumbnail.webp")
    end
  end

  struct TrafficRequest
    getter path : String
    getter resource : String
    getter kind : Symbol

    def initialize(@path, @kind)
      @resource = path.byte_slice(3, path.bytesize - 3)
    end
  end

  def self.generate_routes(count : Int32) : Array(RouteDefinition)
    raise ArgumentError.new("route count must be positive") unless count > 0

    routes = Array(RouteDefinition).new(count)
    static_count = count * 45 // 100
    variable_count = count * 40 // 100
    nested_count = count * 5 // 100
    constrained_count = count * 5 // 100
    glob_count = count - static_count - variable_count - nested_count - constrained_count
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
      routes << RouteDefinition.new(
        "/api/v#{index % 3 + 1}/account_#{index}/:id/revision",
        payload,
        :constrained,
        {"id" => /\A\d+\z/}
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
    grouped = routes.group_by(&.kind)
    traffic = Array(TrafficRequest).new(size)

    size.times do |index|
      bucket = index % 100
      kind = case bucket
             when 0..44  then :static
             when 45..84 then :variable
             when 85..89 then :nested
             when 90..94 then :constrained
             when 95..97 then :glob
             else             include_misses ? :notfound : :static
             end

      if kind == :notfound
        traffic << TrafficRequest.new("get/api/v9/missing_#{index % 17}/#{index}", kind)
        next
      end

      definitions = grouped[kind]
      hot_count = {definitions.size, 24}.min
      route_index = if index % 10 < 7
                      index % hot_count
                    else
                      (index.to_i64 * 131 % definitions.size).to_i
                    end
      definition = definitions[route_index]
      traffic << TrafficRequest.new("get#{definition.matching_resource(index)}", kind)
    end

    traffic
  end
end
