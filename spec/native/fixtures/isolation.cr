require "../../../src/amber/native"
require "../../../examples/hybrid_counter/shared"

macro finished
  {% for constant in ["HTTP", "OpenSSL", "LibSSL", "LibXML", "YAML"] %}
    {% if @top_level.has_constant?(constant) %}
      {% raise "Native facade imported forbidden dependency: #{constant.id}" %}
    {% end %}
  {% end %}
  {% for constant in ["Server", "Controller", "Router", "Mailer", "Jobs", "WebSockets"] %}
    {% if Amber.has_constant?(constant) %}
      {% raise "Native facade imported server-only module: #{constant.id}" %}
    {% end %}
  {% end %}
end

module NativeFacadeProof
  def self.run : Int32
    state = HybridCounter::State.new
    raise "Native schema rejected valid value" unless state.rename("Android").success?
    raise "Native schema accepted empty name" unless state.rename("").failure?
    42.times { state.increment }
    config = Amber::Native::Configuration.new("dev.amber.nativeproof")
    lifecycle = Amber::Native::Lifecycle.new
    lifecycle.start
    lifecycle.background
    lifecycle.foreground
    lifecycle.stop
    raise "Native lifecycle failed" unless lifecycle.state.stopped?
    raise "Native configuration failed" unless config.environment.production?
    state.count
  end
end

puts "Amber native facade: #{NativeFacadeProof.run}"
