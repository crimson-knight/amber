module Amber
  module Pipe
    # This class picks the correct pipeline based on the request
    # and executes it.
    class Pipeline < Base
      getter pipeline
      getter valve : Symbol

      def initialize(@valve = :web)
        @pipeline = {} of Symbol => Array(HTTP::Handler)
        @pipeline[@valve] = [] of HTTP::Handler
        @drain = {} of Symbol => (HTTP::Handler | (HTTP::Server::Context ->))
      end

      def call(context : HTTP::Server::Context)
        request = context.request
        raise Amber::Exceptions::RouteNotFound.new(request) unless request.valid_route?

        if context.websocket?
          context.process_websocket_request
        else
          route = request.route

          # Check request-level constraint if the matched route has one
          if constraint = route.request_constraint
            unless constraint.matches?(request)
              raise Amber::Exceptions::RouteNotFound.new(request)
            end
          end

          if drain = @drain[route.valve]
            drain.call(context)
            context.finalize_response!
          end
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
