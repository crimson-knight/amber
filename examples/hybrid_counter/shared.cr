require "../../src/amber/native"

module HybridCounter
  class Rename < Amber::Schema::Definition
    field :name, String, required: true, min_length: 2, max_length: 64
  end

  # Both entrypoints own an instance of this same store and use case. No router,
  # renderer or platform-service type is needed to exercise application rules.
  class State
    getter count = 0
    getter name = "Guest"

    def increment : Int32
      @count += 1
    end

    def rename(input : String) : Amber::Schema::LegacyResult
      schema = Rename.new({"name" => JSON::Any.new(input.strip)})
      result = schema.validate
      @name = schema.name.not_nil! if result.success?
      result
    end

    def snapshot : String
      {name: @name, count: @count}.to_json
    end
  end
end
