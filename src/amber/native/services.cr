module Amber::Native
  class ServiceError < Exception
    enum Code
      Unavailable
      PermissionDenied
      Cancelled
      InvalidInput
      IO
      Network
    end

    getter code : Code

    def initialize(@code : Code, message : String)
      super(message)
    end
  end

  # Cancel is idempotent. Every accepted operation must complete exactly once,
  # including cancellation, on the host's application thread. Adapters own any
  # per-request work/JNI references and must release those resources by completion.
  # Shared host-owned worker pools may outlive an individual operation. A rejected
  # submission throws before returning an Operation; it has no completion callback.
  abstract class Operation
    abstract def cancel : Nil
  end

  struct HTTPRequest
    getter method : String
    getter url : String
    getter headers : Hash(String, String)
    getter body : Bytes?
    getter timeout_ms : Int32

    def initialize(@method : String, @url : String,
                   headers = {} of String => String, body : Bytes? = nil,
                   @timeout_ms = 30_000)
      raise ArgumentError.new("timeout_ms must be positive") unless @timeout_ms > 0
      @headers = headers.dup
      @body = body.try(&.dup)
    end
  end

  struct HTTPResponse
    getter status : Int32
    getter headers : Hash(String, Array(String))
    getter body : Bytes

    def initialize(@status : Int32, @headers : Hash(String, Array(String)), @body : Bytes)
    end
  end

  # Native HTTP uses platform TLS/trust and never requires Crystal OpenSSL.
  abstract class HTTPClient
    abstract def request(request : HTTPRequest, &completion : HTTPResponse | ServiceError ->) : Operation
  end

  # Storage is an app-scoped key/value store, not an ORM/database promise.
  abstract class Storage
    abstract def read(key : String, &completion : String? | ServiceError ->) : Operation
    abstract def write(key : String, value : String, &completion : Nil | ServiceError ->) : Operation
    abstract def delete(key : String, &completion : Nil | ServiceError ->) : Operation
  end

  # Secrets must use platform protected storage; never silently fall back to
  # ordinary preferences or embed server credentials in a mobile application.
  abstract class Secrets
    abstract def read(key : String, &completion : String? | ServiceError ->) : Operation
    abstract def write(key : String, value : String, &completion : Nil | ServiceError ->) : Operation
    abstract def delete(key : String, &completion : Nil | ServiceError ->) : Operation
  end

  # Paths are relative to app-private storage. An adapter rejects absolute paths
  # and traversal. User-selected documents belong to a separate permission API.
  abstract class Files
    abstract def read(path : String, &completion : Bytes | ServiceError ->) : Operation
    abstract def write(path : String, data : Bytes, &completion : Nil | ServiceError ->) : Operation
    abstract def delete(path : String, &completion : Nil | ServiceError ->) : Operation
  end

  struct Notification
    getter id : Int32
    getter channel : String
    getter title : String
    getter body : String

    def initialize(@id : Int32, @channel : String, @title : String, @body : String)
    end
  end

  abstract class Notifications
    abstract def request_permission(&completion : Bool | ServiceError ->) : Operation
    abstract def post(notification : Notification, &completion : Nil | ServiceError ->) : Operation
    abstract def cancel(id : Int32, &completion : Nil | ServiceError ->) : Operation
  end
end
