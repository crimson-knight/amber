require "./adapters/session_adapter"
require "./adapters/pubsub_adapter"
require "./adapters/memory_session_adapter"
require "./adapters/memory_pubsub_adapter"

# Conditionally require Redis adapters if available
{% if flag?(:redis) %}
  require "./adapters/redis_session_adapter"
  require "./adapters/redis_pubsub_adapter"
{% end %}

require "./adapters/adapter_factory"

module Amber::Adapters
  # This module contains all the abstract adapter interfaces for Amber framework components.
  #
  # ## Available Adapters
  #
  # ### SessionAdapter
  # Abstract interface for session storage backends. Implementations can use any storage
  # system (Redis, database, in-memory, file-based, etc.) as long as they provide the
  # required session operations.
  #
  # ### PubSubAdapter  
  # Abstract interface for pub/sub messaging backends used by WebSocket channels.
  # Implementations can use any messaging system (Redis pub/sub, message queues,
  # in-memory broadcasting, etc.) as long as they provide publish/subscribe functionality.
  #
  # ## Creating Custom Adapters
  #
  # To create a custom adapter, inherit from one of the abstract base classes and
  # implement all the required abstract methods:
  #
  # ```
  # class MyCustomSessionAdapter < Amber::Adapters::SessionAdapter
  #   def initialize(@my_storage : MyStorageSystem)
  #   end
  #
  #   def get(session_id : String, key : String) : String?
  #     @my_storage.fetch("sessions:#{session_id}:#{key}")
  #   end
  #
  #   # ... implement other required methods
  # end
  # ```
  #
  # ## Configuration
  #
  # Configure adapters in your application settings:
  #
  # ```
  # # Using custom adapters
  # settings.session_adapter = MyCustomSessionAdapter.new(my_storage)
  # settings.websocket_adapter = MyCustomPubSubAdapter.new(my_broker)
  # ```
end 