require "asset_pipeline/ui/android/application"
require "../../src/amber/native/android_notifications"

module NativeNotificationsProbe
  @@notifications : Amber::Native::Notifications = Amber::Native::Android::Notifications.new
  @@status = "Local notifications ready"
  @@closing = false
  @@denied_started = false
  @@checks = 0
  ID = 84621

  def self.verify(condition : Bool) : Nil
    raise "Notification assertion failed at check #{@@checks + 1}" unless condition
    @@checks += 1
  end

  def self.status(value : String) : Nil
    @@status = value
    UI::Android::Application.invalidate
  end

  def self.request : Nil
    status("Permission pending")
    returned = false
    @@notifications.request_permission do |result|
      verify(returned)
      status(result.is_a?(Bool) ? "Permission result: #{result}" : "Permission error: #{result.code}")
    end
    returned = true
    GC.collect
  end

  def self.batch : Nil
    status("Permission batch pending")
    remaining = 64
    returned = false
    64.times do |index|
      token = @@notifications.request_permission do |result|
        verify(returned)
        verify(index.even? ? result.is_a?(Amber::Native::ServiceError) && result.code.cancelled? : result == true)
        remaining -= 1
        if remaining == 0
          verify(UI::Android::Services.pending_count == 0)
          status("Permission granted: 32, cancelled: 32")
        end
      end
      if index.even?
        token.cancel
        token.cancel
      end
    end
    begin
      @@notifications.request_permission { raise "Overflow request completed" }
      raise "Queue overflow accepted"
    rescue error : Amber::Native::ServiceError
      verify(error.code.unavailable?)
    end
    returned = true
    GC.collect
  end

  def self.post(channel = "ap_contract_updates", title = "Hello 雪 😀", expected = "Posted", body = "A local notification from Crystal.") : Nil
    returned = false
    @@notifications.post(Amber::Native::Notification.new(ID, channel, title, body)) do |result|
      verify(returned)
      if expected == "Posted" || expected == "Updated" || expected == "Maximum posted"
        verify(result.nil?)
      elsif expected == "Unknown channel rejected"
        verify(result.is_a?(Amber::Native::ServiceError) && result.code.invalid_input?)
      else
        verify(result.is_a?(Amber::Native::ServiceError) && result.code.permission_denied?)
      end
      status(expected)
    end
    returned = true
  end

  def self.cancel : Nil
    returned = false
    @@notifications.cancel(ID) do |result|
      verify(returned && result.nil?)
      status("Cancelled")
    end
    returned = true
  end

  def self.start_close : Nil
    return if @@closing
    @@closing = true
    32.times { @@notifications.request_permission { |result| verify(result.is_a?(Amber::Native::ServiceError) && result.code.cancelled?) } }
    GC.collect
  end

  def self.start_denied : Nil
    return if @@denied_started
    @@denied_started = true
    returned = false
    remaining = 3
    checked = ->(result : Bool | Nil | Amber::Native::ServiceError) {
      verify(returned && result.is_a?(Amber::Native::ServiceError) && result.code.permission_denied?)
      remaining -= 1
      if remaining == 0
        verify(UI::Android::Services.pending_count == 0)
        status("Notifications require explicit app opt-in")
      end
      nil
    }
    @@notifications.request_permission { |result| checked.call(result) }
    @@notifications.post(Amber::Native::Notification.new(ID, "ap_contract_updates", "Not posted", "")) { |result| checked.call(result) }
    @@notifications.cancel(ID) { |result| checked.call(result) }
    returned = true
    GC.collect
  end

  def self.screen : UI::View
    UI::VStack.new(8.0, UI::Alignment::Leading).tap do |root|
      root << UI::Label.new("Amber local notification contract")
      root << UI::Label.new(@@status)
      root << UI::Button.new("Request permission") { request }
      root << UI::Button.new("Request 64") { batch }
      root << UI::Button.new("Post notification") { post }
      root << UI::Button.new("Update notification") { post(title: "Updated 雪 😀", expected: "Updated") }
      root << UI::Button.new("Post while denied") { post(expected: "Permission denied correctly") }
      root << UI::Button.new("Post blocked channel") { post(channel: "ap_contract_blocked", expected: "Blocked channel respected") }
      root << UI::Button.new("Post unknown channel") { post(channel: "unknown", expected: "Unknown channel rejected") }
      root << UI::Button.new("Post maximum text") { post(title: "T" * 1024, body: "B" * 1024, expected: "Maximum posted") }
      root << UI::Button.new("Cancel notification") { cancel }
    end
  end
end

UI::Android::Application.configure do |route|
  NativeNotificationsProbe.start_close if route == "notifications-close"
  NativeNotificationsProbe.start_denied if route == "notifications-denied"
  NativeNotificationsProbe.screen
end
