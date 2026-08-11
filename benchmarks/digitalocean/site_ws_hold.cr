require "http/web_socket"
require "json"

url = ARGV[0]? || "ws://127.0.0.1:41019/ws"
requested = (ARGV[1]? || "100").to_i
hold_seconds = (ARGV[2]? || "45").to_i
connect_timeout = (ARGV[3]? || "60").to_i.seconds

results = Channel(Tuple(Bool, String?)).new(requested)
sockets = [] of HTTP::WebSocket
sockets_mutex = Mutex.new
started_at = Time.instant

requested.times do
  spawn do
    begin
      socket = HTTP::WebSocket.new(URI.parse(url))
      socket.send({event: "join", topic: "site:proof", payload: {} of String => String}.to_json)
      sockets_mutex.synchronize { sockets << socket }
      results.send({true, nil})
      socket.run
    rescue ex
      results.send({false, "#{ex.class}: #{ex.message}"})
    end
  end
end

connected = 0
errors = Hash(String, Int32).new(0)
received = 0
deadline = Time.instant + connect_timeout

while received < requested
  remaining = deadline - Time.instant
  break if remaining <= Time::Span.zero

  select
  when result = results.receive
    received += 1
    if result[0]
      connected += 1
    else
      errors[result[1] || "unknown"] += 1
    end
  when timeout(remaining)
    break
  end
end

puts({
  event:             "connections_ready",
  url:               url,
  requested:         requested,
  connected:         connected,
  connection_errors: errors,
  connect_seconds:   (Time.instant - started_at).total_seconds.round(3),
  hold_seconds:      hold_seconds,
}.to_json)
STDOUT.flush

sleep hold_seconds.seconds
sockets_mutex.synchronize do
  sockets.each do |socket|
    begin
      socket.close
    rescue
    end
  end
end

puts({event: "connections_closed", connected: connected}.to_json)
