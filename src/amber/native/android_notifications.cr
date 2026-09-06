# Optional immediate local Android notifications. Permission is an explicit call.
require "../native"
require "asset_pipeline/ui/android/application"
require "./notification_wire"

module Amber::Native::Android
  class NotificationsOperation < Amber::Native::Operation
    def initialize(@token : UI::Android::Services::Operation)
    end

    def cancel : Nil
      @token.cancel
    rescue UI::Android::Services::Unavailable
      raise ServiceError.new(ServiceError::Code::Unavailable, "Notification cancellation unavailable")
    end
  end

  class Notifications < Amber::Native::Notifications
    def request_permission(&completion : Bool | ServiceError ->) : Operation
      submit(NotificationWire.permission) do |reply|
        result = if !reply.status.ok?
                   service_error(reply.status)
                 elsif reply.data.size == 1 && reply.data[0] <= 1
                   reply.data[0] == 1
                 else
                   ServiceError.new(ServiceError::Code::IO, "Invalid Android permission result")
                 end
        completion.call(result)
      end
    end

    def post(notification : Amber::Native::Notification, &completion : Nil | ServiceError ->) : Operation
      packet = NotificationWire.post(notification)
      submit(packet) { |reply| completion.call(reply.status.ok? ? nil : service_error(reply.status)) }
    rescue ArgumentError
      raise ServiceError.new(ServiceError::Code::InvalidInput, "Invalid notification")
    end

    def cancel(id : Int32, &completion : Nil | ServiceError ->) : Operation
      packet = NotificationWire.cancel(id)
      submit(packet) { |reply| completion.call(reply.status.ok? ? nil : service_error(reply.status)) }
    rescue ArgumentError
      raise ServiceError.new(ServiceError::Code::InvalidInput, "Invalid notification id")
    end

    private def submit(packet : Bytes, &completion : UI::Android::Services::Reply -> Nil) : Operation
      NotificationsOperation.new(UI::Android::Services.notifications(packet, &completion))
    rescue UI::Android::Services::Unavailable
      raise ServiceError.new(ServiceError::Code::Unavailable, "Notification service unavailable or queue full")
    end

    private def service_error(status : UI::Android::Services::Status) : ServiceError
      code = case status
             when .unavailable?       then ServiceError::Code::Unavailable
             when .permission_denied? then ServiceError::Code::PermissionDenied
             when .cancelled?         then ServiceError::Code::Cancelled
             when .invalid_input?     then ServiceError::Code::InvalidInput
             else                          ServiceError::Code::IO
             end
      ServiceError.new(code, "Android notifications: #{code}")
    end
  end
end
