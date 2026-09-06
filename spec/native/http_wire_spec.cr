require "spec"
require "../../src/amber/native/http_wire"

private def response_packet(status = 201, headers = [{"Set-Cookie", "a=1"}, {"Set-Cookie", "b=2"}], body = Bytes[0, 255, 42])
  io = IO::Memory.new
  [1, status, headers.size].each { |value| io.write_bytes(value, IO::ByteFormat::BigEndian) }
  headers.each do |name, value|
    [name, value].each do |field|
      io.write_bytes(field.bytesize, IO::ByteFormat::BigEndian)
      io.write(field.to_slice)
    end
  end
  io.write_bytes(body.size, IO::ByteFormat::BigEndian)
  io.write(body)
  io.to_slice
end

describe Amber::Native::Android::HTTPWire do
  it "encodes owned request data as big endian lengths and binary bytes" do
    body = Bytes[0, 255, 42]
    request = Amber::Native::HTTPRequest.new("POST", "https://example.test/", {"X-Test" => "value"}, body, 500)
    body[0] = 99
    bytes = Amber::Native::Android::HTTPWire.encode(request)
    io = IO::Memory.new(bytes)
    io.read_bytes(Int32, IO::ByteFormat::BigEndian).should eq(1)
    io.read_bytes(Int32, IO::ByteFormat::BigEndian).should eq(500)
    bytes[-3, 3].should eq(Bytes[0, 255, 42])
  end

  it "preserves binary error response bodies and repeated normalized headers" do
    result = Amber::Native::Android::HTTPWire.decode(response_packet(status: 422)).as(Amber::Native::HTTPResponse)
    result.status.should eq(422)
    result.body.should eq(Bytes[0, 255, 42])
    result.headers["set-cookie"].should eq(["a=1", "b=2"])
  end

  it "rejects every truncated response, trailing data, and invalid metadata" do
    bytes = response_packet
    bytes.size.times do |size|
      Amber::Native::Android::HTTPWire.decode(bytes[0, size]).as(Amber::Native::ServiceError).code.network?.should be_true
    end
    bad = [response_packet(status: 99), response_packet(status: 600), response_packet(headers: [{"", "x"}]), response_packet(headers: [{"X", String.new(Bytes[255])}])]
    tail = IO::Memory.new
    tail.write(bytes); tail.write_byte(1)
    bad << tail.to_slice
    bad.each { |packet| Amber::Native::Android::HTTPWire.decode(packet).should be_a(Amber::Native::ServiceError) }
  end

  it "rejects oversized requests and invalid encoding before accepting an operation" do
    requests = [
      Amber::Native::HTTPRequest.new("POST", "https://localhost/", body: Bytes.new(921_601)),
      Amber::Native::HTTPRequest.new("GET", "https://localhost/", timeout_ms: 120_001),
      Amber::Native::HTTPRequest.new("GET", "https://localhost/", {"X" => "x" * 32_768}),
      Amber::Native::HTTPRequest.new("GET", String.new(Bytes[255])),
    ]
    requests.each { |request| expect_raises(ArgumentError) { Amber::Native::Android::HTTPWire.encode(request) } }
  end
end
