{% if flag?(:redis) %}
  require "redis"
{% end %}

require "./session_adapter"

module Amber::Adapters
  {% if flag?(:redis) %}
  # Redis implementation of the SessionAdapter interface.
  #
  # This adapter provides persistent session storage using Redis as the backend.
  # It supports all standard session operations including expiration, batch operations,
  # and efficient key-value storage.
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
  # AdapterFactory.register_session_adapter("redis") do
  #   RedisSessionAdapter.new(redis_url: ENV["REDIS_URL"]?)
  # end
  # ```
  #
  # ## Usage
  #
  # ```yaml
  # # In your configuration
  # session:
  #   adapter: "redis"
  #   key: "myapp.session"
  #   expires: 3600
  # ```
  class RedisSessionAdapter < SessionAdapter
    getter redis : Redis?
    property redis_url : String?

    def initialize(@redis_url : String? = nil)
      {% if @type.has_constant?("Redis") %}
        @redis = Redis.new(url: @redis_url || ENV["REDIS_URL"]? || "redis://localhost:6379")
      {% else %}
        @redis = nil
        raise ArgumentError.new("Redis library not available. Please add 'redis' to your shard.yml dependencies.")
      {% end %}
    end

    def get(session_id : String, key : String) : String?
      check_redis_availability
      redis.not_nil!.hget(session_id, key)
    end

    def set(session_id : String, key : String, value : String) : Nil
      check_redis_availability
      redis.not_nil!.hset(session_id, key, value)
    end

    def delete(session_id : String, key : String) : Nil
      check_redis_availability
      redis.not_nil!.hdel(session_id, key)
    end

    def destroy(session_id : String) : Nil
      check_redis_availability
      redis.not_nil!.del(session_id)
    end

    def exists?(session_id : String, key : String) : Bool
      check_redis_availability
      redis.not_nil!.hexists(session_id, key) == 1
    end

    def keys(session_id : String) : Array(String)
      check_redis_availability
      redis.not_nil!.hkeys(session_id)
    end

    def values(session_id : String) : Array(String)
      check_redis_availability
      redis.not_nil!.hvals(session_id)
    end

    def to_hash(session_id : String) : Hash(String, String)
      check_redis_availability
      redis.not_nil!.hgetall(session_id)
    end

    def empty?(session_id : String) : Bool
      check_redis_availability
      redis.not_nil!.hlen(session_id) == 0
    end

    def expire(session_id : String, seconds : Int32) : Nil
      check_redis_availability
      redis.not_nil!.expire(session_id, seconds)
    end

    def batch_set(session_id : String, hash : Hash(String, String)) : Nil
      check_redis_availability
      redis.not_nil!.hmset(session_id, hash)
    end

    def clear : Nil
      check_redis_availability
      # Note: This is a destructive operation that clears ALL keys in the Redis database
      # In a production environment, you might want to be more selective
      redis.not_nil!.flushdb
    end



    private def check_redis_availability
      unless @redis
        raise RuntimeError.new("Redis connection not available. Ensure Redis is running and the redis shard is installed.")
      end
    end

    # Factory method for easier instantiation
    def self.create(redis_url : String? = nil) : RedisSessionAdapter
      new(redis_url)
    end
  end
  {% end %}
end 