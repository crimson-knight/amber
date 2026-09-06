require "json"

module Amber::Native
  enum Environment
    Development
    Test
    Production
  end

  # Explicit public application configuration; never reads ENV or server YAML,
  # changes the working directory, or contains deployment secrets by default.
  class Configuration
    getter application_id : String
    getter environment : Environment
    @values : Hash(String, JSON::Any)

    def initialize(@application_id : String, @environment = Environment::Production,
                   values = {} of String => JSON::Any)
      raise ArgumentError.new("application_id cannot be empty") if @application_id.strip.empty?
      @values = JSON.parse(values.to_json).as_h
    end

    # Return a deep copy so callers cannot mutate host configuration indirectly.
    def [](key : String) : JSON::Any
      JSON.parse(@values[key].to_json)
    end

    def []?(key : String) : JSON::Any?
      @values[key]?.try { |value| JSON.parse(value.to_json) }
    end

    def values : Hash(String, JSON::Any)
      JSON.parse(@values.to_json).as_h
    end
  end
end
