require "asset_pipeline/ui/android/application"
require "../../src/amber/native/android_files"

module NativeFilesProbe
  @@files : Amber::Native::Files = Amber::Native::Android::Files.new
  @@started = false
  @@closing_started = false
  @@status = "File contract starting"
  @@steps = [] of Proc(Nil)
  @@checks = 0
  PATH      = "contract/雪/😀.bin"
  VALUE     = Bytes.new(260) { |i| (i % 256).to_u8 }
  MAX_VALUE = Bytes.new(1_048_576) { |i| (i % 256).to_u8 }

  def self.verify(condition : Bool) : Nil
    raise "File contract assertion failed at check #{@@checks + 1}" unless condition
    @@checks += 1
  end

  def self.next_step : Nil
    if step = @@steps.shift?
      step.call
    else
      verify(UI::Android::Services.pending_count == 0)
      @@status = "File contract passed: #{@@checks} checks"
      UI::Android::Application.invalidate
    end
  end

  def self.start : Nil
    return if @@started
    @@started = true
    @@steps << -> { @@files.delete(PATH) { |result| verify(result.nil?); next_step }; nil }
    @@steps << -> {
      @@files.read(PATH) { |result| verify(result.is_a?(Amber::Native::ServiceError) && result.code == Amber::Native::ServiceError::Code::IO); next_step }
      nil
    }
    @@steps << -> {
      submitted = false
      data = VALUE.dup
      @@files.write(PATH, data) { |result| verify(submitted && result.nil?); next_step }
      data.fill(42_u8)
      submitted = true
      GC.collect
      nil
    }
    @@steps << -> { @@files.read(PATH) { |result| verify(result == VALUE); next_step }; nil }
    @@steps << -> {
      paths = ["", "../escape", "/absolute", "a//b", "a\u0000b", ".ap-pending"]
      remaining = paths.size
      paths.each do |path|
        @@files.write(path, VALUE) do |result|
          verify(result.is_a?(Amber::Native::ServiceError) && result.code.invalid_input?)
          remaining -= 1
          next_step if remaining == 0
        end
      end
      nil
    }
    @@steps << -> {
      @@files.read(String.new(Bytes[255])) do |result|
        verify(result.is_a?(Amber::Native::ServiceError) && result.code.invalid_input?)
        next_step
      end
      nil
    }
    @@steps << -> {
      before = UI::Android::Services.pending_count
      begin
        @@files.write(PATH, Bytes.new(1_048_577)) { raise "Rejected request completed" }
        raise "Oversized file was accepted"
      rescue error : Amber::Native::ServiceError
        verify(error.code.invalid_input?)
        verify(UI::Android::Services.pending_count == before)
      end
      next_step
      nil
    }
    @@steps << -> { @@files.read(PATH) { |result| verify(result == VALUE); next_step }; nil }
    @@steps << -> {
      token = @@files.read(PATH) do |result|
        verify(result.is_a?(Amber::Native::ServiceError) && result.code.cancelled?)
        next_step
      end
      token.cancel
      token.cancel
      nil
    }
    @@steps << -> {
      remaining = 64
      64.times do |index|
        token = @@files.read(PATH) do |result|
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
        @@files.read(PATH) { raise "Overflow request completed" }
        raise "Queue overflow was accepted"
      rescue error : Amber::Native::ServiceError
        verify(error.code.unavailable?)
      end
      GC.collect
      nil
    }
    @@steps << -> { @@files.write(PATH, MAX_VALUE) { |result| verify(result.nil?); next_step }; nil }
    @@steps << -> { @@files.read(PATH) { |result| verify(result == MAX_VALUE); next_step }; nil }
    @@steps << -> { @@files.write(PATH, Bytes.empty) { |result| verify(result.nil?); next_step }; nil }
    @@steps << -> { @@files.read(PATH) { |result| verify(result == Bytes.empty); next_step }; nil }
    @@steps << -> { @@files.delete(PATH) { |result| verify(result.nil?); next_step }; nil }
    @@steps << -> {
      @@files.read(PATH) { |result| verify(result.is_a?(Amber::Native::ServiceError) && result.code == Amber::Native::ServiceError::Code::IO); next_step }
      nil
    }
    @@steps << -> { @@files.write(PATH, VALUE) { |result| verify(result.nil?); next_step }; nil }
    next_step
  end

  def self.start_close : Nil
    return if @@closing_started
    @@closing_started = true
    32.times do
      @@files.read(PATH) { |result| verify(result.is_a?(Amber::Native::ServiceError) && result.code.cancelled?) }
    end
    GC.collect
  end

  def self.reopen : Nil
    return if @@started
    @@started = true
    # No write on this route: require the previous process's binary payload.
    @@files.read(PATH) do |result|
      verify(result == VALUE)
      verify(UI::Android::Services.pending_count == 0)
      @@status = "Binary file restored after process restart"
      UI::Android::Application.invalidate
    end
  end

  def self.screen : UI::View
    UI::VStack.new(12.0, UI::Alignment::Leading).tap do |root|
      root << UI::Label.new("Amber app-private file contract")
      root << UI::Label.new(@@status)
    end
  end
end

UI::Android::Application.configure do |route|
  NativeFilesProbe.start if route == "files-contract"
  NativeFilesProbe.reopen if route == "files-reopen"
  NativeFilesProbe.start_close if route == "files-close"
  NativeFilesProbe.screen
end
