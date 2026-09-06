module Amber::Native
  # Application processes are explicit objects, not OS processes or server jobs.
  # Hosts serialize these hooks on their application thread. Do not block in a
  # hook; platform adapters deliver asynchronous results back to the same thread.
  abstract class ProcessManager
    def start : Nil
    end

    def foreground : Nil
    end

    def background : Nil
    end

    def stop : Nil
    end
  end

  class Lifecycle
    enum State
      Created
      Foreground
      Background
      Stopped
      Failed
    end

    getter state = State::Created
    @managers : Array(ProcessManager)
    @started = [] of ProcessManager
    @transitioning = false

    def initialize(managers : Enumerable(ProcessManager) = [] of ProcessManager)
      @managers = managers.map(&.as(ProcessManager)).to_a
    end

    # A visible host starts a new session once, or resumes the existing one.
    # Activity recreation must reuse this object, not restart process managers.
    def activate : Nil
      @state.created? ? start : foreground
    end

    # Repeated host notifications are harmless. A stopped or failed session is
    # terminal: create another Lifecycle for a new logical application session.
    def start : Nil
      return if @state.foreground? && !@transitioning
      transition(State::Created, State::Foreground) do
        @managers.each do |manager|
          @started << manager
          manager.start
        end
        @started.each(&.foreground)
      end
    end

    def foreground : Nil
      return if @state.foreground? && !@transitioning
      transition(State::Background, State::Foreground) { @started.each(&.foreground) }
    end

    def background : Nil
      return if @state.background? && !@transitioning
      transition(State::Foreground, State::Background) { @started.reverse_each(&.background) }
    end

    # Stop every manager, even if one throws. Release in reverse acquisition order.
    def stop : Nil
      raise ArgumentError.new("Lifecycle transition is already in progress") if @transitioning
      return if @state.stopped? || @state.failed?
      @transitioning = true
      begin
        error = release_managers
        @state = error ? State::Failed : State::Stopped
        raise error if error
      ensure
        @transitioning = false
      end
    end

    private def transition(expected : State, target : State, & : ->) : Nil
      raise ArgumentError.new("Lifecycle transition is already in progress") if @transitioning
      unless @state == expected
        raise ArgumentError.new("Cannot transition from #{@state} to #{target}; expected #{expected}")
      end
      @transitioning = true
      begin
        yield
        @state = target
      rescue error
        release_managers
        @state = State::Failed
        raise error
      ensure
        @transitioning = false
      end
    end

    private def release_managers : Exception?
      first_error = nil.as(Exception?)
      @started.reverse_each do |manager|
        begin
          manager.stop
        rescue error
          first_error ||= error
        end
      end
      @started.clear
      first_error
    end
  end
end
