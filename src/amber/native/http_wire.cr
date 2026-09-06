require "../native"

# Android service wire v1. Kept separate from the JNI adapter for shared contract
# tests. Length-prefixed UTF-8 metadata, binary body, signed big-endian Int32s.
module Amber::Native::Android::HTTPWire
  MAX_BODY   =   921_600
  MAX_PACKET = 1_048_576

  def self.encode(request : HTTPRequest) : Bytes
    raise ArgumentError.new("HTTP input exceeds limits") unless request.timeout_ms <= 120_000 && request.url.bytesize <= 8192 && request.method.bytesize <= 16 && request.headers.size <= 128 && (request.body.try(&.size) || 0) <= MAX_BODY
    header_bytes = request.headers.sum { |name, value| name.bytesize.to_i64 + value.bytesize }
    raise ArgumentError.new("HTTP headers exceed limits") if header_bytes > 32_768
    io = IO::Memory.new
    io.write_bytes(1_i32, IO::ByteFormat::BigEndian)
    io.write_bytes(request.timeout_ms, IO::ByteFormat::BigEndian)
    write_string(io, request.method)
    write_string(io, request.url)
    io.write_bytes(request.headers.size, IO::ByteFormat::BigEndian)
    request.headers.each { |name, value| write_string(io, name); write_string(io, value) }
    io.write_bytes(request.body.try(&.size) || -1_i32, IO::ByteFormat::BigEndian)
    request.body.try { |body| io.write(body) }
    raise ArgumentError.new("HTTP packet exceeds limits") if io.size > MAX_PACKET
    io.to_slice
  end

  private def self.write_string(io : IO, value : String) : Nil
    raise ArgumentError.new("Invalid HTTP metadata encoding") unless value.valid_encoding?
    io.write_bytes(value.bytesize, IO::ByteFormat::BigEndian)
    io.write(value.to_slice)
  end

  private def self.read_string(io : IO::Memory, max : Int32) : String
    size = io.read_bytes(Int32, IO::ByteFormat::BigEndian)
    raise ArgumentError.new("Invalid HTTP field size") unless 0 <= size <= max && size <= io.size - io.pos
    bytes = Bytes.new(size)
    io.read_fully(bytes)
    value = String.new(bytes)
    raise ArgumentError.new("Invalid HTTP metadata encoding") unless value.valid_encoding?
    value
  end

  def self.decode(bytes : Bytes) : HTTPResponse | ServiceError
    raise ArgumentError.new("Invalid HTTP packet size") if bytes.size > MAX_PACKET
    io = IO::Memory.new(bytes)
    raise ArgumentError.new("Invalid HTTP wire version") unless io.read_bytes(Int32, IO::ByteFormat::BigEndian) == 1
    status = io.read_bytes(Int32, IO::ByteFormat::BigEndian)
    count = io.read_bytes(Int32, IO::ByteFormat::BigEndian)
    raise ArgumentError.new("Invalid HTTP response metadata") unless 100 <= status <= 599 && 0 <= count <= 128
    headers = {} of String => Array(String)
    header_bytes = 0
    count.times do
      name = read_string(io, 32_768)
      value = read_string(io, 32_768)
      header_bytes += name.bytesize + value.bytesize
      raise ArgumentError.new("Invalid HTTP response headers") if header_bytes > 32_768 || name.empty?
      (headers[name.downcase] ||= [] of String) << value
    end
    size = io.read_bytes(Int32, IO::ByteFormat::BigEndian)
    raise ArgumentError.new("Invalid HTTP response body") unless 0 <= size <= MAX_BODY && size == io.size - io.pos
    body = Bytes.new(size)
    io.read_fully(body)
    HTTPResponse.new(status, headers, body)
  rescue ArgumentError | IO::EOFError
    ServiceError.new(ServiceError::Code::Network, "Invalid Android HTTP response")
  end
end
