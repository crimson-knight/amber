require "asset_pipeline/ui/android/application"
require "../../src/amber/native/android_storage"

module NativeStorageProbe
  @@storage : Amber::Native::Storage = Amber::Native::Android::Storage.new
  @@started = false
  @@status = "Storage contract starting"
  @@steps = [] of Proc(Nil)
  @@checks = 0
  KEY = "contract/雪/😀\u0000key"
  VALUE = "before\u0000after — café 雪 😀"

  def self.verify(condition : Bool) : Nil
    raise "Storage contract assertion failed at check #{@@checks + 1}" unless condition
    @@checks += 1
  end

  def self.next_step : Nil
    if step = @@steps.shift?
      step.call
    else
      verify(UI::Android::Services.pending_count == 0)
      @@status = "Storage contract passed: #{@@checks} checks"
      UI::Android::Application.invalidate
    end
  end

  def self.start : Nil
    return if @@started
    @@started = true
    @@steps << -> {
      @@storage.delete(KEY) { |result| verify(result.nil?); next_step }
      nil
    }
    @@steps << -> {
      @@storage.read(KEY) { |result| verify(result.nil?); next_step }
      nil
    }
    @@steps << -> {
      submitted = false
      @@storage.write(KEY, VALUE) { |result| verify(submitted && result.nil?); next_step }
      submitted = true
      GC.collect
      nil
    }
    @@steps << -> {
      @@storage.read(KEY) { |result| verify(result == VALUE); next_step }
      nil
    }
    @@steps << -> {
      @@storage.read("") do |result|
        verify(result.is_a?(Amber::Native::ServiceError) && result.code.invalid_input?)
        next_step
      end
      nil
    }
    @@steps << -> {
      @@storage.write(KEY, String.new(Bytes[255])) do |result|
        verify(result.is_a?(Amber::Native::ServiceError) && result.code.invalid_input?)
        next_step
      end
      nil
    }
    @@steps << -> {
      @@storage.read(KEY) { |result| verify(result == VALUE); next_step }
      nil
    }
    @@steps << -> {
      token = @@storage.read(KEY) do |result|
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
        @@storage.write(KEY, "x" * 1_048_577) { raise "Rejected operation completed" }
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
        token = @@storage.read(KEY) do |result|
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
        @@storage.read(KEY) { raise "Overflow operation completed" }
        raise "Queue overflow was accepted"
      rescue error : Amber::Native::ServiceError
        verify(error.code.unavailable?)
      end
      GC.collect
      nil
    }
    @@steps << -> {
      @@storage.delete(KEY) { |result| verify(result.nil?); next_step }
      nil
    }
    @@steps << -> {
      @@storage.read(KEY) { |result| verify(result.nil?); next_step }
      nil
    }
    next_step
  end

  def self.screen : UI::View
    UI::VStack.new(12.0, UI::Alignment::Leading).tap do |root|
      root << UI::Label.new("Amber storage contract")
      root << UI::Label.new(@@status)
    end
  end
end

UI::Android::Application.on_lifecycle { |event| NativeStorageProbe.start if event.foreground? }
UI::Android::Application.configure { |_route| NativeStorageProbe.screen }
