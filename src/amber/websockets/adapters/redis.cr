{% if flag?(:redis) %}
  require "redis"
{% end %}

module Amber::WebSockets::Adapters
  {% if flag?(:redis) %}
  # Allows websocket connections through redis pub/sub.
  class RedisAdapter
    {% if @type.has_constant?("Redis") %}
      @subscriber : Redis
      @publisher : Redis
    {% else %}
      @subscriber : Nil = nil
      @publisher : Nil = nil
    {% end %}

    def self.instance
      @@instance ||= new
    end

    # Establish subscribe and publish connections to Redis
    def initialize
      {% if @type.has_constant?("Redis") %}
        @subscriber = Redis.new(url: Amber.settings.redis_url)
        @publisher = Redis.new(url: Amber.settings.redis_url)
      {% else %}
        raise RuntimeError.new("Redis library not available. Please add 'redis' to your shard.yml dependencies or use adapter-based WebSocket pub/sub.")
      {% end %}
    end

    # Publish the *message* to the redis publisher with topic *topic_path*
    def publish(topic_path, client_socket, message)
      {% if @type.has_constant?("Redis") %}
        @publisher.publish(topic_path, {sender: client_socket.id, msg: message}.to_json)
      {% else %}
        raise RuntimeError.new("Redis library not available. Please add 'redis' to your shard.yml dependencies or use adapter-based WebSocket pub/sub.")
      {% end %}
    end

    # Add a redis subscriber with topic *topic_path*
    def on_message(topic_path, listener)
      {% if @type.has_constant?("Redis") %}
        spawn do
          @subscriber.subscribe(topic_path) do |on|
            on.message do |_, m|
              msg = JSON.parse(m)
              sender_id = msg["sender"].as_s
              message = msg["msg"]
              listener.call(sender_id, message)
            end
          end
        end
      {% else %}
        raise RuntimeError.new("Redis library not available. Please add 'redis' to your shard.yml dependencies or use adapter-based WebSocket pub/sub.")
      {% end %}
    end
  end
  {% end %}
end
