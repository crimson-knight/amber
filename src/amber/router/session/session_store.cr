module Amber::Router::Session
  class Store
    getter config : Hash(Symbol, Symbol | String | Int32)
    getter cookies : Cookies::Store

    def initialize(@cookies, @config)
    end

    def build : Session::AbstractStore
      # Check if adapter is specified in config
      if adapter_specified?
        return build_adapter_session
      end

      # Fallback to legacy behavior for backwards compatibility
      return RedisStore.build(redis_store, cookies, config) if redis?
      CookieStore.build(cookie_store, config)
    end

    private def build_adapter_session : Session::AdapterSessionStore
      adapter_name = config[:adapter]?.try(&.to_s) || "memory"
      adapter = Amber::Adapters::AdapterFactory.create_session_adapter(adapter_name)
      AdapterSessionStore.build(adapter, cookies, config)
    end

    private def adapter_specified? : Bool
      config.has_key?(:adapter) && !config[:adapter]?.nil?
    end

    private def cookie_store
      encrypted_cookie? ? cookies.encrypted : cookies.signed
    end

    private def redis_store
      {% if @type.has_constant?("Redis") %}
        Redis.new(url: ENV["REDIS_URL"]? || Amber.settings.redis_url)
      {% else %}
        raise RuntimeError.new("Redis library not available. Please add 'redis' to your shard.yml dependencies or use adapter-based sessions.")
      {% end %}
    end

    private def redis?
      store == :redis
    end

    private def encrypted_cookie?
      store == :encrypted_cookie
    end

    private def store
      config[:store]
    end

    private def secret
      config[:secret]
    end
  end
end
