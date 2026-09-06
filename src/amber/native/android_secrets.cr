# Optional Android adapter. No dependency on ordinary plaintext Storage.
require "../native"
require "asset_pipeline/ui/android/application"

module Amber::Native::Android
  class SecretsOperation < Amber::Native::Operation
    def initialize(@token : UI::Android::Services::Operation)
    end

    def cancel : Nil
      @token.cancel
    rescue UI::Android::Services::Unavailable
      raise ServiceError.new(ServiceError::Code::Unavailable, "Protected storage cancellation unavailable")
    end
  end

  class Secrets < Amber::Native::Secrets
    def read(key : String, &completion : String? | ServiceError ->) : Operation
      submit(1, key) do |reply|
        completion.call(case reply.status
        when .ok?        then String.new(reply.data)
        when .not_found? then nil
        else                  service_error(reply.status)
        end)
      end
    end

    def write(key : String, value : String, &completion : Nil | ServiceError ->) : Operation
      submit(2, key, value) { |reply| completion.call(reply.status.ok? ? nil : service_error(reply.status)) }
    end

    def delete(key : String, &completion : Nil | ServiceError ->) : Operation
      submit(3, key) { |reply| completion.call(reply.status.ok? ? nil : service_error(reply.status)) }
    end

    private def submit(operation : Int32, key : String, value : String = "", &completion : UI::Android::Services::Reply -> Nil) : Operation
      SecretsOperation.new(UI::Android::Services.secrets(operation, key, value, &completion))
    rescue UI::Android::Services::Unavailable
      raise ServiceError.new(ServiceError::Code::Unavailable, "Protected storage unavailable or queue full")
    rescue ArgumentError
      raise ServiceError.new(ServiceError::Code::InvalidInput, "Invalid protected storage input")
    end

    private def service_error(status : UI::Android::Services::Status) : ServiceError
      code = case status
             when .unavailable?       then ServiceError::Code::Unavailable
             when .permission_denied? then ServiceError::Code::PermissionDenied
             when .cancelled?         then ServiceError::Code::Cancelled
             when .invalid_input?     then ServiceError::Code::InvalidInput
             else                          ServiceError::Code::IO
             end
      ServiceError.new(code, "Android protected storage: #{code}")
    end
  end
end
