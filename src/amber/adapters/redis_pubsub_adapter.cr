{% if flag?(:redis) %}
  require "redis"
{% end %}

require "./pubsub_adapter"
require "json"

module Amber::Adapters
  {% if flag?(:redis) %}
  # Redis implementation of the PubSubAdapter interface.
  #
  # This adapter provides scalable pub/sub messaging using Redis as the backend.
  # It supports multi-server deployments where WebSocket connections can be
  # distributed across multiple application instances.
  #
  # ## Requirements
  #
  # - Redis server must be running
  # - `redis` Crystal shard must be installed
  #
  # ## Configuration
  #
  # ```crystal
  # # Register the Redis adapter
  # AdapterFactory.register_pubsub_adapter("redis") do
  #   RedisPubSubAdapter.new(redis_url: ENV["REDIS_URL"]?)
  # end
  # ```
  #
  # ## Usage
  #
  # ```yaml
  # # In your configuration
  # pubsub:
  #   adapter: "redis"
  # ```
  class RedisPubSubAdapter < PubSubAdapter
    getter publisher : Redis?
    getter subscriber : Redis?
    property redis_url : String?

    # Map of topic -> array of subscription handlers
    @subscriptions = Hash(String, Array((String, JSON::Any) -> Nil)).new
    @subscription_fibers = Hash(String, Fiber).new

    def initialize(@redis_url : String? = nil)
      {% if @type.has_constant?("Redis") %}
        url = @redis_url || ENV["REDIS_URL"]? || "redis://localhost:6379"
        @publisher = Redis.new(url: url)
        @subscriber = Redis.new(url: url)
      {% else %}
        @publisher = nil
        @subscriber = nil
        raise ArgumentError.new("Redis library not available. Please add 'redis' to your shard.yml dependencies.")
      {% end %}
    end

    def publish(topic : String, sender_id : String, message : JSON::Any) : Nil
      check_redis_availability
      
      # Wrap the message with sender information
      wrapped_message = JSON.build do |json|
        json.object do
          json.field "sender_id", sender_id
          json.field "message", message
        end
      end
      
      publisher.not_nil!.publish(topic, wrapped_message)
    end

    def subscribe(topic : String, &block : (String, JSON::Any) -> Nil) : Nil
      check_redis_availability
      
      # Add the block to our subscriptions
      @subscriptions[topic] ||= Array((String, JSON::Any) -> Nil).new
      @subscriptions[topic] << block
      
      # Start subscription fiber if not already running for this topic
      unless @subscription_fibers.has_key?(topic)
        @subscription_fibers[topic] = spawn do
          begin
            subscriber.not_nil!.subscribe(topic) do |message|
              if handlers = @subscriptions[topic]?
                begin
                  parsed_message = JSON.parse(message)
                  sender_id = parsed_message["sender_id"].as_s
                  inner_message = parsed_message["message"]
                  
                  # Call all handlers for this topic
                  handlers.each do |handler|
                    begin
                      handler.call(sender_id, inner_message)
                    rescue ex
                      # Log the error but don't crash the subscription
                      Log.error(exception: ex) { "Error in subscription handler for topic #{topic}" }
                    end
                  end
                rescue ex
                  Log.error(exception: ex) { "Error parsing Redis message for topic #{topic}: #{message}" }
                end
              end
            end
          rescue ex
            Log.error(exception: ex) { "Redis subscription error for topic #{topic}" }
            # Clean up fiber reference
            @subscription_fibers.delete(topic)
          end
        end
      end
    end

    def unsubscribe(topic : String) : Nil
      check_redis_availability
      
      # Remove all handlers for this topic
      if handlers = @subscriptions.delete(topic)
        # Stop the subscription fiber
        if fiber = @subscription_fibers.delete(topic)
          # Note: Redis doesn't provide a clean way to unsubscribe from a specific topic
          # within a subscription block, so we'll need to restart the subscriber
          begin
            subscriber.not_nil!.unsubscribe(topic)
          rescue
            # Subscriber connection might be in use, that's okay
          end
        end
      end
    end

    def unsubscribe_all : Nil
      check_redis_availability
      
      @subscriptions.clear
      @subscription_fibers.each_value(&.terminate_fiber)
      @subscription_fibers.clear
      
      begin
        subscriber.not_nil!.unsubscribe
      rescue
        # Connection might be in use, that's okay
      end
    end

    def close : Nil
      unsubscribe_all
      
      @publisher.try(&.close)
      @subscriber.try(&.close)
      @publisher = nil
      @subscriber = nil
    end

    private def check_redis_availability
      unless @publisher && @subscriber
        raise RuntimeError.new("Redis connection not available. Ensure Redis is running and the redis shard is installed.")
      end
    end

    # Factory method for easier instantiation
    def self.create(redis_url : String? = nil) : RedisPubSubAdapter
      new(redis_url)
    end
  end
  {% end %}
end 