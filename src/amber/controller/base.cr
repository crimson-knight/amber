require "http"

require "./filters"
require "./helpers/*"
require "./schema_integration"

module Amber::Controller
  class Base
    include Helpers::CSRF
    include Helpers::Redirect
    include Helpers::Render
    include Helpers::Responders
    include Helpers::Route
    include Helpers::I18n
    include Callbacks

    protected getter context : HTTP::Server::Context
    # Keep the original params declaration for backward compatibility
    # The actual implementation is now provided by SchemaIntegration module
    # protected getter params : Amber::Validators::Params

    delegate :client_ip,
      :cookies,
      :delete?,
      :flash,
      :format,
      :get?,
      :halt!,
      :head?,
      :patch?,
      :port,
      :post?,
      :put?,
      :request,
      :requested_url,
      :response,
      :route,
      :session,
      :valve,
      :websocket?,
      to: context

    def initialize(@context : HTTP::Server::Context)
      # Initialize original_params for backward compatibility
      # The SchemaIntegration module handles params through its override
      @original_params = Amber::Validators::Params.new(context.params)
    end
  end
end
