require "option_parser"
require "../src/amber"

module AmberPrecisionRouteSlotProbe
  extend self

  TARGET_PATH = "/bench/users/42/details"
  PREFIX      = "/bench/users/"
  SUFFIX      = "/details"
  SLASH_BYTE  = '/'.ord.to_u8

  @@sink = 0

  struct ParamSpan
    getter key : Symbol
    getter start_index : Int32
    getter end_index : Int32

    def initialize(@key : Symbol = :none, @start_index : Int32 = 0, @end_index : Int32 = 0)
    end

    @[AlwaysInline]
    def size : Int32
      @end_index - @start_index
    end

    @[AlwaysInline]
    def value(path : String) : String
      path.byte_slice(@start_index, size)
    end
  end

  class RouteSlot
    @params = StaticArray(ParamSpan, 4).new(ParamSpan.new)

    property payload : Symbol?
    getter param_count : Int32

    def initialize
      @payload = nil
      @param_count = 0
    end

    @[AlwaysInline]
    def reset : Nil
      @payload = nil
      @param_count = 0
    end

    @[AlwaysInline]
    def found? : Bool
      !@payload.nil?
    end

    @[AlwaysInline]
    def add_param(key : Symbol, start_index : Int32, end_index : Int32) : Nil
      @params[@param_count] = ParamSpan.new(key, start_index, end_index)
      @param_count += 1
    end

    @[AlwaysInline]
    def param_size(key : Symbol) : Int32
      index = 0
      while index < @param_count
        span = @params[index]
        return span.size if span.key == key
        index += 1
      end

      0
    end

    def param_value(path : String, key : Symbol) : String?
      index = 0
      while index < @param_count
        span = @params[index]
        return span.value(path) if span.key == key
        index += 1
      end
    end
  end

  class StaticUserRouteMatcher
    @[AlwaysInline]
    def match(path : String, slot : RouteSlot) : Bool
      slot.reset
      return false unless path.starts_with?(PREFIX)
      return false unless path.ends_with?(SUFFIX)

      id_start = PREFIX.bytesize
      id_end = path.bytesize - SUFFIX.bytesize
      return false unless id_end > id_start

      index = id_start
      while index < id_end
        return false if path.byte_at(index) == SLASH_BYTE
        index += 1
      end

      slot.payload = :user_details
      slot.add_param(:id, id_start, id_end)
      true
    end
  end

  def build_router(route_count : Int32) : Amber::Router::RouteSet(Symbol)
    router = Amber::Router::RouteSet(Symbol).new

    (0...route_count).each do |index|
      router.add("/bench/fixed/#{index}", :fixed)
    end

    router.add("/bench/users/:id/details", :user_details)
    router
  end

  @[AlwaysInline]
  def consume(value : Int32) : Nil
    @@sink &+= value
  end

  def run_for(duration_seconds : Float64, &block : ->) : Int64
    deadline = Time.instant + duration_seconds.seconds
    iterations = 0_i64

    while Time.instant < deadline
      yield
      iterations += 1
    end

    iterations
  end

  def run(scenario : String, duration_seconds : Float64, route_count : Int32) : Nil
    router = build_router(route_count)
    matcher = StaticUserRouteMatcher.new
    slot = RouteSlot.new

    GC.collect
    stats_before = GC.stats

    iterations = case scenario
                 when "amber_best"
                   run_for(duration_seconds) do
                     result = router.find_experimental_best(TARGET_PATH)
                     consume(result.found? ? 1 : 0)
                   end
                 when "amber_best_param"
                   run_for(duration_seconds) do
                     result = router.find_experimental_best(TARGET_PATH)
                     consume(result.params["id"].bytesize)
                   end
                 when "slot_match"
                   run_for(duration_seconds) do
                     matcher.match(TARGET_PATH, slot)
                     consume(slot.found? ? 1 : 0)
                   end
                 when "slot_param_size"
                   run_for(duration_seconds) do
                     matcher.match(TARGET_PATH, slot)
                     consume(slot.param_size(:id))
                   end
                 when "slot_param_value"
                   run_for(duration_seconds) do
                     matcher.match(TARGET_PATH, slot)
                     consume(slot.param_value(TARGET_PATH, :id).not_nil!.bytesize)
                   end
                 else
                   raise "Unknown scenario: #{scenario}"
                 end

    stats_after = GC.stats
    allocated_bytes = stats_after.total_bytes - stats_before.total_bytes

    puts "Scenario: #{scenario}"
    puts "Routes: #{route_count}"
    puts "Iterations: #{iterations}"
    puts "Duration: #{duration_seconds}"
    puts "IPS: #{iterations / duration_seconds}"
    puts "Allocated bytes: #{allocated_bytes}"
    puts "Bytes per iteration: #{allocated_bytes.to_f / iterations}"
    puts "Sink: #{@@sink}"
  end
end

scenario = "amber_best"
duration_seconds = 5.0
route_count = 1_000

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal run benchmarks/precision_route_slot_probe.cr -- [options]"

  parser.on("--scenario=NAME", "Scenario: amber_best, amber_best_param, slot_match, slot_param_size, slot_param_value") do |value|
    scenario = value
  end

  parser.on("--duration=SECONDS", "Wall-clock run duration") do |value|
    duration_seconds = value.to_f
  end

  parser.on("--routes=COUNT", "Number of fixed routes to add before the dynamic target route") do |value|
    route_count = value.to_i
  end
end

AmberPrecisionRouteSlotProbe.run(scenario, duration_seconds, route_count)
