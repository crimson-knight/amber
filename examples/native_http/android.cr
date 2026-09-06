require "asset_pipeline/ui/android/application"
require "../../src/amber/native/android_http"
require "../../src/amber/native/android_storage"

module NativeHTTPProbe
  @@client : Amber::Native::HTTPClient = Amber::Native::Android::HTTPClient.new
  @@storage : Amber::Native::Storage = Amber::Native::Android::Storage.new
  @@started = false
  @@closing_started = false
  @@denied_started = false
  @@status = "HTTP adapter ready"
  @@checks = 0
  @@steps = [] of Proc(Nil)
  @@active = [] of Amber::Native::Operation
  BODY = Bytes[0, 255, 13, 10, 42]
  BASE = "https://localhost:18443"

  def self.verify(value : Bool) : Nil
    raise "HTTP contract failed at check #{@@checks + 1}" unless value
    @@checks += 1
  end

  def self.next_step : Nil
    if step = @@steps.shift?
      step.call
    else
      verify(UI::Android::Services.pending_count == 0)
      @@status = "HTTP contract passed"
      UI::Android::Application.invalidate
    end
  end

  def self.response(value : Amber::Native::HTTPResponse | Amber::Native::ServiceError) : Amber::Native::HTTPResponse
    verify(value.is_a?(Amber::Native::HTTPResponse))
    value.as(Amber::Native::HTTPResponse)
  end

  def self.expect_error(url : String, code : Amber::Native::ServiceError::Code, timeout = 3000) : Nil
    @@steps << -> {
      @@client.request(Amber::Native::HTTPRequest.new("GET", url, timeout_ms: timeout)) do |result|
        verify(result.is_a?(Amber::Native::ServiceError) && result.code == code)
        next_step
      end
      nil
    }
  end

  def self.start : Nil
    return if @@started
    @@started = true
    @@status = "HTTP contract running"
    @@steps << -> {
      submitted = false
      @@client.request(Amber::Native::HTTPRequest.new("GET", "#{BASE}/ok")) do |result|
        verify(submitted)
        value = response(result)
        verify(value.status == 200)
        verify(value.body == "TLS OK 雪 😀\u0000".to_slice)
        verify(value.headers["set-cookie"] == ["a=1", "b=2"])
        next_step
      end
      submitted = true
      GC.collect
      nil
    }
    ["POST", "PATCH"].each do |method|
      @@steps << -> {
        @@client.request(Amber::Native::HTTPRequest.new(method, "#{BASE}/echo", {"Authorization" => "Bearer contract-only"}, BODY)) do |result|
          value = response(result)
          verify(value.status == 200 && value.body == BODY)
          next_step
        end
        nil
      }
    end
    @@steps << -> {
      @@client.request(Amber::Native::HTTPRequest.new("GET", "#{BASE}/error")) do |result|
        value = response(result)
        verify(value.status == 422 && value.body == BODY)
        next_step
      end
      nil
    }
    @@steps << -> {
      @@client.request(Amber::Native::HTTPRequest.new("GET", "#{BASE}/redirect", {"Authorization" => "Bearer contract-only"})) do |result|
        value = response(result)
        verify(value.status == 302 && value.headers["location"] == ["#{BASE}/must-not-follow"])
        next_step
      end
      nil
    }
    @@steps << -> {
      @@client.request(Amber::Native::HTTPRequest.new("HEAD", "#{BASE}/head")) do |result|
        value = response(result)
        verify(value.status == 200 && value.body.empty?)
        next_step
      end
      nil
    }
    expect_error("#{BASE}/large", Amber::Native::ServiceError::Code::Network)
    expect_error("#{BASE}/chunk-large", Amber::Native::ServiceError::Code::Network)
    expect_error("#{BASE}/slow", Amber::Native::ServiceError::Code::Network, 150)
    expect_error("https://localhost:18444/ok", Amber::Native::ServiceError::Code::Network)
    expect_error("https://localhost:18445/ok", Amber::Native::ServiceError::Code::Network)
    expect_error("http://localhost:18446/ok", Amber::Native::ServiceError::Code::Network)
    expect_error("file:///private", Amber::Native::ServiceError::Code::InvalidInput)
    @@steps << -> {
      @@client.request(Amber::Native::HTTPRequest.new("GET", "#{BASE}/must-not-follow", {"X-Test" => "bad\r\nInjected: 1"})) do |result|
        verify(result.is_a?(Amber::Native::ServiceError) && result.code.invalid_input?)
        next_step
      end
      nil
    }
    @@steps << -> {
      token = @@client.request(Amber::Native::HTTPRequest.new("GET", "#{BASE}/cancel-queued")) do |result|
        verify(result.is_a?(Amber::Native::ServiceError) && result.code.cancelled?)
        next_step
      end
      token.cancel; token.cancel
      nil
    }
    @@steps << -> {
      before = UI::Android::Services.pending_count
      begin
        @@client.request(Amber::Native::HTTPRequest.new("POST", "#{BASE}/must-not-follow", body: Bytes.new(921_601))) { raise "Rejected request completed" }
        raise "Oversized request accepted"
      rescue error : Amber::Native::ServiceError
        verify(error.code.invalid_input?)
        verify(UI::Android::Services.pending_count == before)
      end
      next_step
      nil
    }
    @@steps << -> {
      remaining = 4
      4.times do
        @@active << @@client.request(Amber::Native::HTTPRequest.new("GET", "#{BASE}/cancel", timeout_ms: 15_000)) do |result|
          verify(result.is_a?(Amber::Native::ServiceError) && result.code.cancelled?)
          remaining -= 1
          next_step if remaining == 0
        end
      end
      # This must complete while all four networking workers are occupied.
      @@storage.read("http-contract/nonexistent-probe") do |result|
        verify(result.nil?)
        @@status = "HTTP cancellation ready"
        UI::Android::Application.invalidate
      end
      GC.collect
      nil
    }
    next_step
  end

  def self.screen : UI::View
    UI::VStack.new(12.0, UI::Alignment::Leading).tap do |root|
      root << UI::Label.new("Amber HTTP contract")
      root << UI::Label.new(@@status)
      root << UI::Label.new("Checks: #{@@checks}")
      root << UI::Button.new("Cancel HTTP requests") { @@active.each { |operation| operation.cancel; operation.cancel } }
    end
  end

  def self.start_close : Nil
    return if @@closing_started
    @@closing_started = true
    @@status = "HTTP close ready"
    4.times do
      @@client.request(Amber::Native::HTTPRequest.new("GET", "#{BASE}/cancel-close", timeout_ms: 15_000)) do |result|
        verify(result.is_a?(Amber::Native::ServiceError) && result.code.cancelled?)
      end
    end
    GC.collect
  end

  def self.start_denied : Nil
    return if @@denied_started
    @@denied_started = true
    @@status = "Checking network permission"
    @@client.request(Amber::Native::HTTPRequest.new("GET", "https://localhost:18443/must-not-follow")) do |result|
      verify(result.is_a?(Amber::Native::ServiceError) && result.code.permission_denied?)
      verify(UI::Android::Services.pending_count == 0)
      @@status = "HTTP permission denied correctly"
      UI::Android::Application.invalidate
    end
  end
end

UI::Android::Application.configure do |route|
  NativeHTTPProbe.start if route == "http-contract"
  NativeHTTPProbe.start_close if route == "http-close"
  NativeHTTPProbe.start_denied if route == "http-denied"
  NativeHTTPProbe.screen
end
