module Amber
  module Pipe
    # This class picks the correct pipeline based on the request
    # and executes it.
    class Pipeline < Base
      getter pipeline
      getter valve : Symbol

      @before_routing = [] of HTTP::Handler
      @before_routing_head : HTTP::Handler? = nil
      @prepared = false

      # Ingress checks must run before route selection, which can inspect form
      # method overrides. Register only during application configuration.
      def before_routing(handler : HTTP::Handler) : Nil
        raise ArgumentError.new("Register ingress handlers before preparing pipelines") if @prepared
        raise ArgumentError.new("Ingress handler is already registered") if @before_routing.any? { |existing| existing.same?(handler) }
        @before_routing << handler
      end

      def initialize(@valve = :web)
        @pipeline = {} of Symbol => Array(HTTP::Handler)
        @pipeline[@valve] = [] of HTTP::Handler
        @drain = {} of Symbol => (HTTP::Handler | (HTTP::Server::Context ->))
      end

      def call(context : HTTP::Server::Context)
        if !@prepared && !@before_routing.empty?
          raise ArgumentError.new("Prepare pipelines before calling registered ingress handlers")
        end
        if head = @before_routing_head
          head.call(context)
        else
          call_routed(context)
        end
      end

      private def call_routed(context : HTTP::Server::Context) : Nil
        raise Amber::Exceptions::RouteNotFound.new(context.request) unless context.valid_route?

        # Check request-level constraint if the matched route has one
        if context.request.valid_route?
          if constraint = context.request.route.request_constraint
            unless constraint.matches?(context.request)
              raise Amber::Exceptions::RouteNotFound.new(context.request)
            end
          end
        end

        if context.websocket?
          context.process_websocket_request
        elsif @drain[context.valve]
          @drain[context.valve].call(context)
          context.finalize_response!
        end
      rescue e : Amber::Exceptions::Base
        Amber::Pipe::Error.new.call(context)
      end

      # Connects pipes to a pipeline to process requests
      def build(valve : Symbol, &)
        @valve = valve
        @pipeline[valve] = [] of HTTP::Handler unless pipeline.has_key? valve
        with DSL::Pipeline.new(self) yield
      end

      def plug(pipe : HTTP::Handler)
        @pipeline[valve] << pipe
      end

      def prepare_pipelines
        pipeline.keys.each do |valve|
          @drain[valve] ||= build_pipeline(pipeline[valve], Amber::Pipe::Controller.new)
        end
        unless @prepared
          unless @before_routing.empty?
            terminal = ->(context : HTTP::Server::Context) { call_routed(context) }
            @before_routing_head = build_pipeline(@before_routing, terminal).as(HTTP::Handler)
          end
          @prepared = true
        end
      end

      def build_pipeline(pipes, last_pipe : HTTP::Handler | (HTTP::Server::Context ->))
        if pipes.empty?
          last_pipe
        else
          0.upto(pipes.size - 2) { |i| pipes[i].next = pipes[i + 1] }
          pipes.last.next = last_pipe if last_pipe
          pipes.first
        end
      end
    end
  end
end
