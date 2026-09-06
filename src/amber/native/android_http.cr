require "../native"
require "asset_pipeline/ui/android/application"
require "./http_wire"

module Amber::Native::Android
  class HTTPOperation < Operation
    def initialize(@operation : UI::Android::Services::Operation)
    end

    def cancel : Nil
      @operation.cancel
    rescue UI::Android::Services::Unavailable
      raise ServiceError.new(ServiceError::Code::Unavailable, "Android HTTP cancellation unavailable")
    end
  end

  class HTTPClient < Amber::Native::HTTPClient
    def request(request : HTTPRequest, &completion : HTTPResponse | ServiceError ->) : Operation
      packet = HTTPWire.encode(request)
      HTTPOperation.new(UI::Android::Services.http(packet) do |reply|
        result = if reply.status.ok?
                   HTTPWire.decode(reply.data)
                 else
                   code = case reply.status
                          when .unavailable?       then ServiceError::Code::Unavailable
                          when .permission_denied? then ServiceError::Code::PermissionDenied
                          when .cancelled?         then ServiceError::Code::Cancelled
                          when .invalid_input?     then ServiceError::Code::InvalidInput
                          when .network?           then ServiceError::Code::Network
                          else                          ServiceError::Code::IO
                          end
                   ServiceError.new(code, "Android HTTP: #{code}")
                 end
        completion.call(result)
      end)
    rescue UI::Android::Services::Unavailable
      raise ServiceError.new(ServiceError::Code::Unavailable, "Android HTTP unavailable or queue full")
    rescue ArgumentError
      raise ServiceError.new(ServiceError::Code::InvalidInput, "Invalid Android HTTP input")
    end
  end
end
