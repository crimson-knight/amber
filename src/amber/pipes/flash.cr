module Amber
  module Pipe
    class Flash < Base
      PARAM_KEY   = "_flash"
      EMPTY_FLASH = "{}"

      # Persists flash messages for the next request. A request that neither
      # sets nor carries a flash message leaves the session untouched, so
      # cookie-free traffic (crawlers, bots, first visits) creates no session.
      def call(context : HTTP::Server::Context) : Nil
        call_next(context)
      ensure
        session = context.session
        serialized_flash = context.flash.to_session
        if serialized_flash == EMPTY_FLASH
          session.delete(PARAM_KEY)
        else
          session[PARAM_KEY] = serialized_flash
        end
      end
    end
  end
end
