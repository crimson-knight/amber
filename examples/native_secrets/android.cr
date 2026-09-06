require "asset_pipeline/ui/android/application"
require "../../src/amber/native/android_secrets"
require "../../src/amber/native/android_storage"

module NativeSecretsProbe
  @@secrets : Amber::Native::Secrets = Amber::Native::Android::Secrets.new
  @@started = false
  @@closing_started = false
  @@status = "Secrets contract starting"
  @@steps = [] of Proc(Nil)
  @@checks = 0
  KEY   = "secrets-contract/雪/😀\u0000key"
  VALUE = "before\u0000after — café 雪 😀"

  def self.verify(condition : Bool) : Nil
    raise "Secrets contract assertion failed at check #{@@checks + 1}" unless condition
    @@checks += 1
  end

  def self.next_step : Nil
    if step = @@steps.shift?
      step.call
    else
      verify(UI::Android::Services.pending_count == 0)
      @@status = "Secrets contract passed: #{@@checks} checks"
      UI::Android::Application.invalidate
    end
  end

  def self.start : Nil
    return if @@started
    @@started = true
    @@steps << -> {
      @@secrets.delete(KEY) { |result| verify(result.nil?); next_step }
      nil
    }
    @@steps << -> {
      @@secrets.read(KEY) { |result| verify(result.nil?); next_step }
      nil
    }
    @@steps << -> {
      submitted = false
      @@secrets.write(KEY, VALUE) { |result| verify(submitted && result.nil?); next_step }
      submitted = true
      GC.collect
      nil
    }
    @@steps << -> {
      @@secrets.read(KEY) { |result| verify(result == VALUE); next_step }
      nil
    }
    @@steps << -> {
      @@secrets.read("") do |result|
        verify(result.is_a?(Amber::Native::ServiceError) && result.code.invalid_input?)
        next_step
      end
      nil
    }
    @@steps << -> {
      @@secrets.write(KEY, String.new(Bytes[255])) do |result|
        verify(result.is_a?(Amber::Native::ServiceError) && result.code.invalid_input?)
        next_step
      end
      nil
    }
    @@steps << -> {
      @@secrets.read(KEY) { |result| verify(result == VALUE); next_step }
      nil
    }
    @@steps << -> {
      token = @@secrets.read(KEY) do |result|
        verify(result.is_a?(Amber::Native::ServiceError) && result.code.cancelled?)
        next_step
      end
      token.cancel
      token.cancel
      nil
    }
    @@steps << -> {
      before = UI::Android::Services.pending_count
      begin
        @@secrets.write(KEY, "x" * 65_537) { raise "Rejected operation completed" }
        raise "Oversized request was accepted"
      rescue error : Amber::Native::ServiceError
        verify(error.code.invalid_input?)
        verify(UI::Android::Services.pending_count == before)
      end
      next_step
      nil
    }
    @@steps << -> {
      remaining = 64
      64.times do |index|
        token = @@secrets.read(KEY) do |result|
          if index.even?
            verify(result.is_a?(Amber::Native::ServiceError) && result.code.cancelled?)
          else
            verify(result == VALUE)
          end
          remaining -= 1
          next_step if remaining == 0
        end
        token.cancel if index.even?
      end
      begin
        @@secrets.read(KEY) { raise "Overflow operation completed" }
        raise "Queue overflow was accepted"
      rescue error : Amber::Native::ServiceError
        verify(error.code.unavailable?)
      end
      GC.collect
      nil
    }
    @@steps << -> {
      Amber::Native::Android::Storage.new.read(KEY) { |result| verify(result.nil?); next_step }
      nil
    }
    @@steps << -> {
      @@secrets.write(KEY, "") { |result| verify(result.nil?); next_step }
      nil
    }
    @@steps << -> {
      @@secrets.read(KEY) { |result| verify(result == ""); next_step }
      nil
    }
    @@steps << -> {
      @@secrets.delete(KEY) { |result| verify(result.nil?); next_step }
      nil
    }
    @@steps << -> {
      @@secrets.read(KEY) { |result| verify(result.nil?); next_step }
      nil
    }
    # Leave only a public, test-only value for the separate-process proof.
    @@steps << -> {
      @@secrets.write(KEY, VALUE) { |result| verify(result.nil?); next_step }
      nil
    }
    next_step
  end

  def self.start_close : Nil
    return if @@closing_started
    @@closing_started = true
    32.times do
      @@secrets.read(KEY) do |result|
        verify(result.is_a?(Amber::Native::ServiceError) && result.code.cancelled?)
      end
    end
    GC.collect
  end

  def self.reopen : Nil
    return if @@started
    @@started = true
    # This route MUST NOT write. Success requires the preceding process's data.
    @@secrets.read(KEY) do |result|
      verify(result == VALUE)
      verify(UI::Android::Services.pending_count == 0)
      @@status = "Protected test value restored after process restart"
      UI::Android::Application.invalidate
    end
  end

  def self.screen : UI::View
    UI::VStack.new(12.0, UI::Alignment::Leading).tap do |root|
      root << UI::Label.new("Amber secrets contract")
      root << UI::Label.new(@@status)
    end
  end
end

UI::Android::Application.configure do |route|
  NativeSecretsProbe.start if route == "secrets-contract"
  NativeSecretsProbe.reopen if route == "secrets-reopen"
  NativeSecretsProbe.start_close if route == "secrets-close"
  NativeSecretsProbe.screen
end
