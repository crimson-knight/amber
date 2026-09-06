require "spec"
require "../../src/amber/native"
require "../../examples/hybrid_counter/shared"

class NativeValueSchema < Amber::Schema::Definition
  field :email, String, required: true, format: "email"
  field :url, String, format: "url"
  field :identifier, UUID, format: "uuid"
  field :age, Int32, min: 18, max: 120
end

class NativeRecordingProcess < Amber::Native::ProcessManager
  property fail_on : String? = nil
  property hook : Proc(Nil)? = nil

  def initialize(@name : String, @events : Array(String))
  end

  private def record(event : String) : Nil
    @events << "#{@name}:#{event}"
    @hook.try(&.call) if event == "start"
    raise "#{@name} failed #{event}" if @fail_on == event
  end

  def start : Nil
    record("start")
  end

  def foreground : Nil
    record("foreground")
  end

  def background : Nil
    record("background")
  end

  def stop : Nil
    record("stop")
  end
end

describe Amber::Native::Configuration do
  it "takes explicit public values without reading or changing server environment" do
    before = ENV["AMBER_ENV"]?
    config = Amber::Native::Configuration.new("dev.amber.test", values: JSON.parse(%({"nested":{"value":1}})).as_h)
    config.environment.production?.should be_true
    config["nested"].as_h["value"] = JSON::Any.new(99_i64)
    config["nested"]["value"].as_i.should eq(1)
    config["missing"]?.should be_nil
    ENV["AMBER_ENV"]?.should eq(before)
  end

  it "rejects an empty application identity" do
    expect_raises(ArgumentError, "application_id cannot be empty") do
      Amber::Native::Configuration.new(" ")
    end
  end
end

describe Amber::Native::Lifecycle do
  it "activates a retained host session without starting its managers again" do
    events = [] of String
    lifecycle = Amber::Native::Lifecycle.new([NativeRecordingProcess.new("app", events)])
    lifecycle.activate
    lifecycle.activate
    3.times do
      lifecycle.background
      lifecycle.activate
    end
    events.count("app:start").should eq(1)
    events.count("app:foreground").should eq(4)
    events.count("app:background").should eq(3)
    lifecycle.stop
    expect_raises(ArgumentError) { lifecycle.activate }
    events.count("app:stop").should eq(1)
  end

  it "serializes lifecycle hooks and ignores duplicate host notifications" do
    events = [] of String
    managers = [NativeRecordingProcess.new("a", events), NativeRecordingProcess.new("b", events)]
    lifecycle = Amber::Native::Lifecycle.new(managers)
    lifecycle.start
    lifecycle.start
    lifecycle.background
    lifecycle.background
    lifecycle.foreground
    lifecycle.foreground
    lifecycle.stop
    lifecycle.stop
    events.should eq(["a:start", "b:start", "a:foreground", "b:foreground",
                      "b:background", "a:background", "a:foreground", "b:foreground", "b:stop", "a:stop"])
    lifecycle.state.stopped?.should be_true
    expect_raises(ArgumentError) { lifecycle.start }
  end

  it "cleans up partial startup in reverse order and keeps the original error" do
    events = [] of String
    a = NativeRecordingProcess.new("a", events)
    b = NativeRecordingProcess.new("b", events)
    b.fail_on = "start"
    a.fail_on = "stop"
    lifecycle = Amber::Native::Lifecycle.new([a, b])
    expect_raises(Exception, "b failed start") { lifecycle.start }
    events.should eq(["a:start", "b:start", "b:stop", "a:stop"])
    lifecycle.state.failed?.should be_true
    lifecycle.stop
    expect_raises(ArgumentError) { lifecycle.foreground }
  end

  it "attempts every cleanup even when one manager fails" do
    events = [] of String
    a = NativeRecordingProcess.new("a", events)
    b = NativeRecordingProcess.new("b", events)
    lifecycle = Amber::Native::Lifecycle.new([a, b])
    lifecycle.start
    b.fail_on = "stop"
    expect_raises(Exception, "b failed stop") { lifecycle.stop }
    events.last(2).should eq(["b:stop", "a:stop"])
    lifecycle.state.failed?.should be_true
  end

  it "rejects reentrant lifecycle changes and releases the failed session" do
    events = [] of String
    manager = NativeRecordingProcess.new("a", events)
    lifecycle = Amber::Native::Lifecycle.new([manager])
    manager.hook = -> { lifecycle.stop }
    expect_raises(ArgumentError, "already in progress") { lifecycle.start }
    lifecycle.state.failed?.should be_true
    events.should eq(["a:start", "a:stop"])
  end

  it "does not run hooks for invalid transitions" do
    lifecycle = Amber::Native::Lifecycle.new
    expect_raises(ArgumentError) { lifecycle.background }
    lifecycle.state.created?.should be_true
    lifecycle.stop
    lifecycle.state.stopped?.should be_true
  end
end

describe "native-safe schema values" do
  it "uses the existing validation and coercion without HTTP parsing" do
    schema = NativeValueSchema.new(JSON.parse(%({"email":"dev@example.com","url":"https://example.com","identifier":"123e4567-e89b-12d3-a456-426614174000","age":"42"})).as_h)
    schema.validate_typed.success?.should be_true
    schema.age.should eq(42)
  end

  it "reports invalid values through the existing typed error contract" do
    result = NativeValueSchema.new(JSON.parse(%({"email":"invalid","url":"not a URL","age":12})).as_h).validate_typed
    result.failure?.should be_true
    result.error.not_nil!.errors.map(&.field).sort.should eq(["age", "email", "url"])
  end

  it "validates supplied file metadata without loading the multipart parser" do
    data = JSON.parse(%({"filename":"photo.PNG","content_type":"image/png","size":42}))
    options = JSON.parse(%({"max_size":100,"allowed_types":["image/png"],"allowed_extensions":[".png"]})).as_h
    Amber::Schema::FileMetadataValidator.validate_file("photo", data, options).should be_empty
    options["max_size"] = JSON::Any.new(10_i64)
    Amber::Schema::FileMetadataValidator.validate_file("photo", data, options).map(&.code).should eq(["file_too_large"])
  end
end

describe HybridCounter::State do
  it "keeps shared use-case validation and state independent of presentation" do
    state = HybridCounter::State.new
    state.rename("  Android  ").success?.should be_true
    42.times { state.increment }
    state.rename(" ").failure?.should be_true
    JSON.parse(state.snapshot)["name"].as_s.should eq("Android")
    state.count.should eq(42)
  end
end
