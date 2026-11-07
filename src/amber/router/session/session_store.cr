module Amber::Router::Session
  # Builds the session store named by `session.store`:
  #
  # - `signed_cookie` (default) and `encrypted_cookie` keep the session in the
  #   visitor's cookie, so the server holds no per-visitor state.
  # - `adapter` keeps it on the server through `session.adapter` (memory,
  #   redis, or a registered custom adapter). `redis` is accepted as a synonym
  #   for configurations written before `adapter` existed.
  class Store
    COOKIE_STORES = [:signed_cookie, :encrypted_cookie]

    getter config : Hash(Symbol, Symbol | String | Int32)
    getter cookies : Cookies::Store

    def initialize(@cookies, @config)
    end

    def build : Session::AbstractStore
      return CookieStore.build(cookie_store, config) if COOKIE_STORES.includes?(store)

      adapter_name = config[:adapter]?.try(&.to_s) || "memory"
      adapter = Amber::Adapters::AdapterFactory.create_session_adapter(adapter_name)
      AdapterSessionStore.build(adapter, cookies, config)
    end

    private def cookie_store
      encrypted_cookie? ? cookies.encrypted : cookies.signed
    end

    private def encrypted_cookie?
      store == :encrypted_cookie
    end

    private def store
      config[:store]
    end
  end
end
