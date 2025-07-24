require "./session_adapter"
require "./pubsub_adapter"
require "./memory_session_adapter"
require "./memory_pubsub_adapter"

# Conditionally require Redis adapters if available
{% if flag?(:redis) %}
  require "./redis_session_adapter"
  require "./redis_pubsub_adapter"
{% end %}

module Amber::Adapters
  # Factory for creating adapter instances based on configuration.
  #
  # This factory provides a pluggable system for creating adapters without
  # requiring hard dependencies on specific implementations. Users can register
  # custom adapters and the factory will instantiate them based on string identifiers.
  #
  # ## Built-in Adapters
  #
  # ### Session Adapters
  # - `"memory"` - MemorySessionAdapter (default, always available)
  # - `"redis"` - RedisSessionAdapter (available when `redis` shard is installed)
  #
  # ### PubSub Adapters  
  # - `"memory"` - MemoryPubSubAdapter (default, always available)
  # - `"redis"` - RedisPubSubAdapter (available when `redis` shard is installed)
  #
  # ## Usage
  #
  # ```
  # # Using built-in adapters
  # session_adapter = AdapterFactory.create_session_adapter("memory")
  # pubsub_adapter = AdapterFactory.create_pubsub_adapter("memory")
  #
  # # Registering custom adapters
  # AdapterFactory.register_session_adapter("custom") do
  #   CustomSessionAdapter.new
  # end
  #
  # AdapterFactory.register_pubsub_adapter("custom") do  
  #   CustomPubSubAdapter.new
  # end
  # ```
  class AdapterFactory
    # Registry for session adapter factories
    @@session_adapters = Hash(String, Proc(SessionAdapter)).new

    # Registry for pub/sub adapter factories  
    @@pubsub_adapters = Hash(String, Proc(PubSubAdapter)).new

    # Initialize with built-in adapters
    @@initialized = false

    # Ensures built-in adapters are registered
    private def self.ensure_initialized
      return if @@initialized
      
      # Register built-in session adapters
      @@session_adapters["memory"] = ->{ MemorySessionAdapter.new.as(SessionAdapter) }
      
      # Register built-in pub/sub adapters
      @@pubsub_adapters["memory"] = ->{ MemoryPubSubAdapter.new.as(PubSubAdapter) }
      
      # Conditionally register Redis adapters if available
      {% if @type.has_constant?("RedisSessionAdapter") %}
        @@session_adapters["redis"] = ->{ RedisSessionAdapter.new.as(SessionAdapter) }
      {% end %}
      
      {% if @type.has_constant?("RedisPubSubAdapter") %}
        @@pubsub_adapters["redis"] = ->{ RedisPubSubAdapter.new.as(PubSubAdapter) }
      {% end %}
      
      @@initialized = true
    end

    # Creates a session adapter instance based on the adapter name.
    #
    # @param adapter_name The string identifier for the adapter type
    # @param options Optional configuration hash for the adapter
    # @return SessionAdapter instance
    # @raises ArgumentError if the adapter is not registered
    def self.create_session_adapter(adapter_name : String, **options) : SessionAdapter
      ensure_initialized
      
      factory = @@session_adapters[adapter_name]?
      raise ArgumentError.new("Unknown session adapter: #{adapter_name}. Available: #{@@session_adapters.keys.join(", ")}") unless factory
      
      factory.call
    end

    # Creates a pub/sub adapter instance based on the adapter name.
    #
    # @param adapter_name The string identifier for the adapter type  
    # @param options Optional configuration hash for the adapter
    # @return PubSubAdapter instance
    # @raises ArgumentError if the adapter is not registered
    def self.create_pubsub_adapter(adapter_name : String, **options) : PubSubAdapter
      ensure_initialized
      
      factory = @@pubsub_adapters[adapter_name]?
      raise ArgumentError.new("Unknown pub/sub adapter: #{adapter_name}. Available: #{@@pubsub_adapters.keys.join(", ")}") unless factory
      
      factory.call
    end

    # Registers a session adapter factory.
    #
    # @param name String identifier for the adapter
    # @param factory Proc that creates the adapter instance
    def self.register_session_adapter(name : String, factory : Proc(SessionAdapter))
      @@session_adapters[name] = factory
    end

    # Registers a session adapter factory using a block.
    #
    # @param name String identifier for the adapter
    # @param block Block that creates the adapter instance
    def self.register_session_adapter(name : String, &block : -> SessionAdapter)
      @@session_adapters[name] = block
    end

    # Registers a pub/sub adapter factory.
    #
    # @param name String identifier for the adapter
    # @param factory Proc that creates the adapter instance
    def self.register_pubsub_adapter(name : String, factory : Proc(PubSubAdapter))
      @@pubsub_adapters[name] = factory
    end

    # Registers a pub/sub adapter factory using a block.
    #
    # @param name String identifier for the adapter  
    # @param block Block that creates the adapter instance
    def self.register_pubsub_adapter(name : String, &block : -> PubSubAdapter)
      @@pubsub_adapters[name] = block
    end

    # Returns a list of available session adapter names.
    def self.available_session_adapters : Array(String)
      ensure_initialized
      @@session_adapters.keys
    end

    # Returns a list of available pub/sub adapter names.
    def self.available_pubsub_adapters : Array(String)
      ensure_initialized
      @@pubsub_adapters.keys
    end

    # Checks if a session adapter is registered.
    def self.session_adapter_registered?(name : String) : Bool
      ensure_initialized
      @@session_adapters.has_key?(name)
    end

    # Checks if a pub/sub adapter is registered.
    def self.pubsub_adapter_registered?(name : String) : Bool
      ensure_initialized
      @@pubsub_adapters.has_key?(name)
    end
  end
end 