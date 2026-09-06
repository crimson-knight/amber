require "../../spec_helper"

module IngressSpec
  class ProbeBody < IO::Memory
    getter reads = 0

    def read(slice : Bytes) : Int32
      @reads += 1
      super
    end
  end

  class Handler
    include HTTP::Handler

    def initialize(@events : Array(String), @label : String, @stop = false)
    end

    def call(context : HTTP::Server::Context)
      @events << @label
      if @stop
        context.response.status_code = 413
        context.response.print("rejected")
      else
        call_next(context)
      end
    end
  end

  describe Amber::Pipe::Pipeline do
    it "rejects before routing or form method-override parsing, even for a missing route" do
      events = [] of String
      pipeline = Amber::Pipe::Pipeline.new
      pipeline.before_routing(Handler.new(events, "ingress", true))
      pipeline.prepare_pipelines
      body = ProbeBody.new("_method=DELETE")
      request = HTTP::Request.new("POST", "/missing-ingress-route",
        HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, body)
      response = create_request_and_return_io(pipeline, request)
      response.status_code.should eq 413
      response.body.should eq "rejected"
      body.reads.should eq 0
      events.should eq ["ingress"]
    end

    it "runs ingress in registration order before normal route middleware" do
      events = [] of String
      pipeline = Amber::Pipe::Pipeline.new
      pipeline.before_routing(Handler.new(events, "first"))
      pipeline.before_routing(Handler.new(events, "second"))
      pipeline.build :web { plug Handler.new(events, "route") }
      Amber::Server.router.draw :web { get "/ingress-order", HelloController, :world }
      pipeline.prepare_pipelines
      # Preparing again must not make an ingress cycle or invoke a handler twice.
      pipeline.prepare_pipelines
      response = create_request_and_return_io(pipeline, HTTP::Request.new("GET", "/ingress-order"))
      response.status_code.should eq 200
      response.body.should eq "Hello World!"
      events.should eq ["first", "second", "route"]
    end

    it "retains normal web form override behavior after a passing ingress" do
      pipeline = Amber::Pipe::Pipeline.new
      pipeline.before_routing(Handler.new([] of String, "pass"))
      pipeline.build :web { }
      Amber::Server.router.draw :web { delete "/ingress-override", HelloController, :destroy }
      pipeline.prepare_pipelines
      request = HTTP::Request.new("POST", "/ingress-override",
        HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, "_method=DELETE")
      response = create_request_and_return_io(pipeline, request)
      response.body.should eq "Destroy"
    end

    it "rejects duplicate handler identity" do
      pipeline = Amber::Pipe::Pipeline.new
      handler = Handler.new([] of String, "only")
      pipeline.before_routing(handler)
      expect_raises(ArgumentError, "already registered") { pipeline.before_routing(handler) }
    end

    it "rejects late registration instead of silently skipping a security policy" do
      pipeline = Amber::Pipe::Pipeline.new
      pipeline.prepare_pipelines
      expect_raises(ArgumentError, "before preparing") do
        pipeline.before_routing(Handler.new([] of String, "late"))
      end
    end

    it "cannot silently skip registered ingress when a caller forgets preparation" do
      pipeline = Amber::Pipe::Pipeline.new
      pipeline.before_routing(Handler.new([] of String, "guard", true))
      expect_raises(ArgumentError, "Prepare pipelines") do
        create_request_and_return_io(pipeline, HTTP::Request.new("GET", "/unprepared-ingress"))
      end
    end
  end

  describe HTTP::Request do
    it "exposes the literal method without consuming a form body or honoring an override header" do
      body = ProbeBody.new("_method=DELETE")
      request = HTTP::Request.new("POST", "/",
        HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded", "X-HTTP-Method-Override" => "PATCH"}, body)
      request.transport_method.should eq "POST"
      body.reads.should eq 0
      request.method.should eq "DELETE"
      request.transport_method.should eq "POST"
    end
  end
end
