# Optional Android app-private binary files. No external document access.
require "../native"
require "asset_pipeline/ui/android/application"

module Amber::Native::Android
  class FilesOperation < Amber::Native::Operation
    def initialize(@token : UI::Android::Services::Operation)
    end

    def cancel : Nil
      @token.cancel
    rescue UI::Android::Services::Unavailable
      raise ServiceError.new(ServiceError::Code::Unavailable, "File cancellation unavailable")
    end
  end

  class Files < Amber::Native::Files
    def read(path : String, &completion : Bytes | ServiceError ->) : Operation
      submit(1, path) { |reply| completion.call(reply.status.ok? ? reply.data : service_error(reply.status)) }
    end

    def write(path : String, data : Bytes, &completion : Nil | ServiceError ->) : Operation
      submit(2, path, data) { |reply| completion.call(reply.status.ok? ? nil : service_error(reply.status)) }
    end

    def delete(path : String, &completion : Nil | ServiceError ->) : Operation
      submit(3, path) { |reply| completion.call(reply.status.ok? ? nil : service_error(reply.status)) }
    end

    private def submit(operation : Int32, path : String, data : Bytes = Bytes.empty, &completion : UI::Android::Services::Reply -> Nil) : Operation
      FilesOperation.new(UI::Android::Services.files(operation, path, data, &completion))
    rescue UI::Android::Services::Unavailable
      raise ServiceError.new(ServiceError::Code::Unavailable, "File service unavailable or queue full")
    rescue ArgumentError
      raise ServiceError.new(ServiceError::Code::InvalidInput, "Invalid file request")
    end

    private def service_error(status : UI::Android::Services::Status) : ServiceError
      code = case status
             when .unavailable?       then ServiceError::Code::Unavailable
             when .permission_denied? then ServiceError::Code::PermissionDenied
             when .cancelled?         then ServiceError::Code::Cancelled
             when .invalid_input?     then ServiceError::Code::InvalidInput
             else                          ServiceError::Code::IO
             end
      ServiceError.new(code, "Android files: #{code}")
    end
  end
end
