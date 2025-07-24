require "uuid"

module Amber::Router::Session
  # Session store implementation that uses the pluggable adapter system.
  #
  # This replaces the hardcoded Redis/Cookie stores with a flexible adapter-based
  # approach that allows users to implement custom session storage backends.
  #
  # The session adapter handles the low-level storage operations while this class
  # provides the higher-level session management logic including session ID
  # generation, cookie handling, and expiration.
  class AdapterSessionStore < AbstractStore
    @id : String?
    getter adapter : Amber::Adapters::SessionAdapter
    property expires : Int32
    property key : String
    property session_id : String
    property cookies : Amber::Router::Cookies::Store

    def self.build(adapter : Amber::Adapters::SessionAdapter, cookies, session)
      new(adapter, cookies, session[:key].to_s, session[:expires].to_i)
    end

    def initialize(@adapter, @cookies, @key, @expires = 120)
      @session_id = current_session || "#{key}:#{id}"
    end

    def id
      @id ||= UUID.random.to_s
    end

    def changed?
      true
    end

    def destroy
      adapter.destroy(session_id)
    end

    def [](key : String | Symbol)
      value = adapter.get(session_id, key.to_s)
      return value if value
      raise KeyError.new "Missing hash key: #{key.inspect}"
    end

    def []?(key : String | Symbol)
      adapter.get(session_id, key.to_s)
    end

    def []=(key : String | Symbol, value)
      adapter.set(session_id, key.to_s, value.to_s)
    end

    def has_key?(key : String | Symbol) : Bool
      adapter.exists?(session_id, key.to_s)
    end

    def keys
      adapter.keys(session_id)
    end

    def values
      adapter.values(session_id)
    end

    def to_h
      adapter.to_hash(session_id)
    end

    def update(hash : Hash(String | Symbol, String))
      # Convert symbol keys to strings for consistency
      string_hash = hash.transform_keys(&.to_s)
      adapter.batch_set(session_id, string_hash)
    end

    def delete(key : String | Symbol)
      adapter.delete(session_id, key.to_s) if has_key?(key.to_s)
    end

    def fetch(key : String | Symbol, default = nil)
      adapter.get(session_id, key.to_s) || default
    end

    def empty?
      adapter.empty?(session_id)
    end

    def set_session
      cookies.encrypted.set(key, session_id, expires: expires_at, http_only: true)

      # Use batch operations for efficiency
      adapter.batch do |batch|
        batch.set(key, session_id)
        batch.expire(@expires) if @expires > 0
      end
    end

    def expires_at
      (Time.utc + expires.seconds) if @expires > 0
    end

    def current_session
      cookies.encrypted[key]
    end
  end
end 