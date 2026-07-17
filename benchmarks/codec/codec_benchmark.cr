require "json"
require "msgpack"
require "option_parser"

module Amber::Benchmarks::Codec
  extend self

  REQUEST_ID = "01J8Z3M5N70000000000421987"
  ACCOUNT_ID = "018f1e2d-3c4b-7a69-8f01-000000004219"
  EMAIL      = "performance@example.com"
  NOTE       = "Created from the mobile checkout flow"
  TAGS       = ["mobile", "priority", "returning"]

  class JsonPayload
    include JSON::Serializable

    getter request_id : String
    getter account_id : String
    getter email : String
    getter quantity : Int32
    getter active : Bool
    getter priority : Int32
    getter tags : Array(String)
    getter note : String

    def initialize(
      @request_id,
      @account_id,
      @email,
      @quantity,
      @active,
      @priority,
      @tags,
      @note,
    )
    end
  end

  class MsgpackMapPayload
    include MessagePack::Serializable

    getter request_id : String
    getter account_id : String
    getter email : String
    getter quantity : Int32
    getter active : Bool
    getter priority : Int32
    getter tags : Array(String)
    getter note : String

    def initialize(
      @request_id,
      @account_id,
      @email,
      @quantity,
      @active,
      @priority,
      @tags,
      @note,
    )
    end
  end

  class MsgpackArrayPayload
    include MessagePack::ArraySerializable

    getter request_id : String
    getter account_id : String
    getter email : String
    getter quantity : Int32
    getter active : Bool
    getter priority : Int32
    getter tags : Array(String)
    getter note : String

    def initialize(
      @request_id,
      @account_id,
      @email,
      @quantity,
      @active,
      @priority,
      @tags,
      @note,
    )
    end
  end

  class FastMsgpackPayload
    REQUEST_ID_KEY = "request_id".to_slice
    ACCOUNT_ID_KEY = "account_id".to_slice
    EMAIL_KEY      = "email".to_slice
    QUANTITY_KEY   = "quantity".to_slice
    ACTIVE_KEY     = "active".to_slice
    PRIORITY_KEY   = "priority".to_slice
    TAGS_KEY       = "tags".to_slice
    NOTE_KEY       = "note".to_slice

    getter request_id : String
    getter account_id : String
    getter email : String
    getter quantity : Int32
    getter active : Bool
    getter priority : Int32
    getter tags : Array(String)
    getter note : String

    def initialize(
      @request_id,
      @account_id,
      @email,
      @quantity,
      @active,
      @priority,
      @tags,
      @note,
    )
    end

    def self.from_msgpack(bytes : Bytes) : self
      cursor = Cursor.new(bytes)
      request_id = account_id = email = note = nil
      quantity = priority = nil
      active = nil
      tags = nil

      cursor.read_map_size.times do
        key = cursor.read_string_slice
        if key == REQUEST_ID_KEY
          request_id = cursor.read_string
        elsif key == ACCOUNT_ID_KEY
          account_id = cursor.read_string
        elsif key == EMAIL_KEY
          email = cursor.read_string
        elsif key == QUANTITY_KEY
          quantity = cursor.read_int.to_i32
        elsif key == ACTIVE_KEY
          active = cursor.read_bool
        elsif key == PRIORITY_KEY
          priority = cursor.read_int.to_i32
        elsif key == TAGS_KEY
          tags = cursor.read_string_array
        elsif key == NOTE_KEY
          note = cursor.read_string
        else
          cursor.skip_value
        end
      end

      new(
        request_id.not_nil!,
        account_id.not_nil!,
        email.not_nil!,
        quantity.not_nil!,
        active.not_nil!,
        priority.not_nil!,
        tags.not_nil!,
        note.not_nil!
      )
    end

    def to_msgpack : Bytes
      io = IO::Memory.new(capacity: 256)
      writer = Writer.new(io)
      writer.write_map_start(8)
      writer.write_string("request_id")
      writer.write_string(request_id)
      writer.write_string("account_id")
      writer.write_string(account_id)
      writer.write_string("email")
      writer.write_string(email)
      writer.write_string("quantity")
      writer.write_int(quantity)
      writer.write_string("active")
      writer.write_bool(active)
      writer.write_string("priority")
      writer.write_int(priority)
      writer.write_string("tags")
      writer.write_string_array(tags)
      writer.write_string("note")
      writer.write_string(note)
      io.to_slice
    end

    class Cursor
      @offset = 0

      def initialize(@bytes : Bytes)
      end

      def read_map_size : Int32
        marker = read_byte
        case marker
        when 0x80_u8..0x8f_u8 then (marker - 0x80).to_i32
        when 0xde_u8          then read_u16.to_i32
        when 0xdf_u8          then read_u32.to_i32
        else                       raise "expected MessagePack map, got 0x#{marker.to_s(16)}"
        end
      end

      def read_array_size : Int32
        marker = read_byte
        case marker
        when 0x90_u8..0x9f_u8 then (marker - 0x90).to_i32
        when 0xdc_u8          then read_u16.to_i32
        when 0xdd_u8          then read_u32.to_i32
        else                       raise "expected MessagePack array, got 0x#{marker.to_s(16)}"
        end
      end

      def read_string_slice : Bytes
        size = read_string_size(read_byte)
        slice = @bytes[@offset, size]
        @offset += size
        slice
      end

      def read_string : String
        String.new(read_string_slice)
      end

      def read_string_array : Array(String)
        Array(String).new(read_array_size) { read_string }
      end

      def read_bool : Bool
        case marker = read_byte
        when 0xc2_u8 then false
        when 0xc3_u8 then true
        else              raise "expected MessagePack bool, got 0x#{marker.to_s(16)}"
        end
      end

      def read_int : Int64
        marker = read_byte
        case marker
        when 0x00_u8..0x7f_u8 then marker.to_i64
        when 0xe0_u8..0xff_u8 then marker.to_i8!.to_i64
        when 0xcc_u8          then read_byte.to_i64
        when 0xcd_u8          then read_u16.to_i64
        when 0xce_u8          then read_u32.to_i64
        when 0xcf_u8          then read_u64.to_i64!
        when 0xd0_u8          then read_byte.to_i8!.to_i64
        when 0xd1_u8          then read_u16.to_i16!.to_i64
        when 0xd2_u8          then read_u32.to_i32!.to_i64
        when 0xd3_u8          then read_u64.to_i64!
        else                       raise "expected MessagePack int, got 0x#{marker.to_s(16)}"
        end
      end

      def skip_value : Nil
        marker = read_byte
        case marker
        when 0x00_u8..0x7f_u8, 0xc0_u8, 0xc2_u8, 0xc3_u8, 0xe0_u8..0xff_u8
        when 0x80_u8..0x8f_u8
          ((marker - 0x80) * 2).times { skip_value }
        when 0x90_u8..0x9f_u8
          (marker - 0x90).times { skip_value }
        when 0xa0_u8..0xbf_u8
          @offset += marker - 0xa0
        when 0xc4_u8, 0xd9_u8
          @offset += read_byte
        when 0xc5_u8, 0xda_u8
          @offset += read_u16
        when 0xc6_u8, 0xdb_u8
          @offset += read_u32.to_i32
        when 0xca_u8          then @offset += 4
        when 0xcb_u8          then @offset += 8
        when 0xcc_u8, 0xd0_u8 then @offset += 1
        when 0xcd_u8, 0xd1_u8 then @offset += 2
        when 0xce_u8, 0xd2_u8 then @offset += 4
        when 0xcf_u8, 0xd3_u8 then @offset += 8
        when 0xdc_u8
          read_u16.times { skip_value }
        when 0xdd_u8
          read_u32.times { skip_value }
        when 0xde_u8
          (read_u16 * 2).times { skip_value }
        when 0xdf_u8
          (read_u32 * 2).times { skip_value }
        else
          raise "unsupported MessagePack marker 0x#{marker.to_s(16)}"
        end
      end

      private def read_string_size(marker : UInt8) : Int32
        case marker
        when 0xa0_u8..0xbf_u8 then (marker - 0xa0).to_i32
        when 0xd9_u8          then read_byte.to_i32
        when 0xda_u8          then read_u16.to_i32
        when 0xdb_u8          then read_u32.to_i32
        else                       raise "expected MessagePack string, got 0x#{marker.to_s(16)}"
        end
      end

      private def read_byte : UInt8
        byte = @bytes[@offset]
        @offset += 1
        byte
      end

      private def read_u16 : UInt16
        value = (@bytes[@offset].to_u16 << 8) | @bytes[@offset + 1].to_u16
        @offset += 2
        value
      end

      private def read_u32 : UInt32
        value = (@bytes[@offset].to_u32 << 24) |
                (@bytes[@offset + 1].to_u32 << 16) |
                (@bytes[@offset + 2].to_u32 << 8) |
                @bytes[@offset + 3].to_u32
        @offset += 4
        value
      end

      private def read_u64 : UInt64
        value = 0_u64
        8.times { value = (value << 8) | read_byte.to_u64 }
        value
      end
    end

    struct Writer
      def initialize(@io : IO)
      end

      def write_map_start(size : Int32) : Nil
        raise "benchmark map is too large" unless size <= 15
        @io.write_byte(0x80_u8 + size.to_u8)
      end

      def write_string(value : String) : Nil
        size = value.bytesize
        if size <= 31
          @io.write_byte(0xa0_u8 + size.to_u8)
        elsif size <= UInt8::MAX
          @io.write_byte(0xd9)
          @io.write_byte(size.to_u8)
        else
          @io.write_byte(0xda)
          @io.write_bytes(size.to_u16, IO::ByteFormat::BigEndian)
        end
        @io.write(value.to_slice)
      end

      def write_int(value : Int32) : Nil
        if value >= 0 && value <= 0x7f
          @io.write_byte(value.to_u8)
        elsif value >= 0 && value <= UInt8::MAX
          @io.write_byte(0xcc)
          @io.write_byte(value.to_u8)
        elsif value >= 0 && value <= UInt16::MAX
          @io.write_byte(0xcd)
          @io.write_bytes(value.to_u16, IO::ByteFormat::BigEndian)
        else
          @io.write_byte(0xd2)
          @io.write_bytes(value, IO::ByteFormat::BigEndian)
        end
      end

      def write_bool(value : Bool) : Nil
        @io.write_byte(value ? 0xc3_u8 : 0xc2_u8)
      end

      def write_string_array(values : Array(String)) : Nil
        raise "benchmark array is too large" unless values.size <= 15
        @io.write_byte(0x90_u8 + values.size.to_u8)
        values.each { |value| write_string(value) }
      end
    end
  end

  alias Work = -> UInt64
  record Lane, name : String, operation : String, work : Work

  PAYLOAD               = JsonPayload.new(REQUEST_ID, ACCOUNT_ID, EMAIL, 7, true, 3, TAGS, NOTE)
  MSGPACK_MAP_PAYLOAD   = MsgpackMapPayload.new(REQUEST_ID, ACCOUNT_ID, EMAIL, 7, true, 3, TAGS, NOTE)
  MSGPACK_ARRAY_PAYLOAD = MsgpackArrayPayload.new(REQUEST_ID, ACCOUNT_ID, EMAIL, 7, true, 3, TAGS, NOTE)
  FAST_MSGPACK_PAYLOAD  = FastMsgpackPayload.new(REQUEST_ID, ACCOUNT_ID, EMAIL, 7, true, 3, TAGS, NOTE)

  JSON_BODY          = PAYLOAD.to_json
  MSGPACK_MAP_BODY   = MSGPACK_MAP_PAYLOAD.to_msgpack
  MSGPACK_ARRAY_BODY = MSGPACK_ARRAY_PAYLOAD.to_msgpack
  FAST_MSGPACK_BODY  = FAST_MSGPACK_PAYLOAD.to_msgpack

  def checksum(payload) : UInt64
    value = payload.request_id.bytesize + payload.account_id.bytesize + payload.email.bytesize
    value += payload.quantity + payload.priority + payload.tags.size + payload.note.bytesize
    value += 1 if payload.active
    value.to_u64
  end

  def bytes_checksum(bytes : Bytes) : UInt64
    bytes.size.to_u64 &+ bytes[0].to_u64 &+ bytes[bytes.size - 1].to_u64
  end

  def signature(payload)
    {
      payload.request_id,
      payload.account_id,
      payload.email,
      payload.quantity,
      payload.active,
      payload.priority,
      payload.tags,
      payload.note,
    }
  end

  def verify! : Nil
    expected = signature(PAYLOAD)
    candidates = [
      signature(JsonPayload.from_json(JSON_BODY)),
      signature(MsgpackMapPayload.from_msgpack(MSGPACK_MAP_BODY)),
      signature(MsgpackMapPayload.from_msgpack(FAST_MSGPACK_BODY)),
      signature(MsgpackArrayPayload.from_msgpack(MSGPACK_ARRAY_BODY)),
      signature(FastMsgpackPayload.from_msgpack(MSGPACK_MAP_BODY)),
      signature(FastMsgpackPayload.from_msgpack(FAST_MSGPACK_BODY)),
    ]
    raise "codec implementations disagree" unless candidates.all? { |candidate| candidate == expected }
  end

  def lanes : Array(Lane)
    [
      Lane.new("json_legacy_params", "decode", -> {
        params = Hash(String, String).new
        parsed = JSON.parse(JSON_BODY)
        params["_json"] = JSON_BODY
        parsed.as_h.each do |key, value|
          params[key] = value.as_s? || value.to_json
        end
        tags = JSON.parse(params["tags"]).as_a
        (params["request_id"].bytesize + params["account_id"].bytesize +
         params["quantity"].to_i + params["priority"].to_i + tags.size).to_u64
      }),
      Lane.new("json_tree", "decode", -> {
        parsed = JSON.parse(JSON_BODY).as_h
        (parsed["request_id"].as_s.bytesize + parsed["account_id"].as_s.bytesize +
         parsed["quantity"].as_i + parsed["priority"].as_i + parsed["tags"].as_a.size).to_u64
      }),
      Lane.new("json_typed", "decode", -> { checksum(JsonPayload.from_json(JSON_BODY)) }),
      Lane.new("msgpack_map", "decode", -> { checksum(MsgpackMapPayload.from_msgpack(MSGPACK_MAP_BODY)) }),
      Lane.new("msgpack_map_zero_copy", "decode", -> { checksum(MsgpackMapPayload.from_msgpack(MSGPACK_MAP_BODY, true)) }),
      Lane.new("msgpack_array", "decode", -> { checksum(MsgpackArrayPayload.from_msgpack(MSGPACK_ARRAY_BODY)) }),
      Lane.new("msgpack_array_zero_copy", "decode", -> { checksum(MsgpackArrayPayload.from_msgpack(MSGPACK_ARRAY_BODY, true)) }),
      Lane.new("msgpack_specialized_map", "decode", -> { checksum(FastMsgpackPayload.from_msgpack(FAST_MSGPACK_BODY)) }),
      Lane.new("json_typed", "encode", -> { bytes_checksum(PAYLOAD.to_json.to_slice) }),
      Lane.new("msgpack_map", "encode", -> { bytes_checksum(MSGPACK_MAP_PAYLOAD.to_msgpack) }),
      Lane.new("msgpack_array", "encode", -> { bytes_checksum(MSGPACK_ARRAY_PAYLOAD.to_msgpack) }),
      Lane.new("msgpack_specialized_map", "encode", -> { bytes_checksum(FAST_MSGPACK_PAYLOAD.to_msgpack) }),
      Lane.new("json_typed", "roundtrip", -> { checksum(JsonPayload.from_json(PAYLOAD.to_json)) }),
      Lane.new("msgpack_map", "roundtrip", -> { checksum(MsgpackMapPayload.from_msgpack(MSGPACK_MAP_PAYLOAD.to_msgpack)) }),
      Lane.new("msgpack_array", "roundtrip", -> { checksum(MsgpackArrayPayload.from_msgpack(MSGPACK_ARRAY_PAYLOAD.to_msgpack)) }),
      Lane.new("msgpack_specialized_map", "roundtrip", -> { checksum(FastMsgpackPayload.from_msgpack(FAST_MSGPACK_PAYLOAD.to_msgpack)) }),
    ]
  end

  def measure(lane : Lane, operations : Int32, repetition : Int32)
    GC.collect
    before = GC.stats
    checksum = 0_u64
    started_at = Time.instant
    operations.times { checksum &+= lane.work.call }
    elapsed = (Time.instant - started_at).total_seconds
    allocated_bytes = GC.stats.total_bytes - before.total_bytes
    {
      name:                lane.name,
      operation:           lane.operation,
      repetition:          repetition,
      operations:          operations,
      elapsed_seconds:     elapsed,
      operations_per_sec:  operations / elapsed,
      ns_per_operation:    elapsed * 1_000_000_000 / operations,
      allocated_bytes:     allocated_bytes,
      bytes_per_operation: allocated_bytes.to_f64 / operations,
      checksum:            checksum,
    }
  end

  def run(operations : Int32, warmup : Int32, repetitions : Int32, output_path : String) : Nil
    verify!
    benchmark_lanes = lanes
    benchmark_lanes.each do |lane|
      checksum = 0_u64
      warmup.times { checksum &+= lane.work.call }
      raise "warmup was optimized away" if checksum == 0
    end

    results = [] of NamedTuple(
      name: String,
      operation: String,
      repetition: Int32,
      operations: Int32,
      elapsed_seconds: Float64,
      operations_per_sec: Float64,
      ns_per_operation: Float64,
      allocated_bytes: UInt64,
      bytes_per_operation: Float64,
      checksum: UInt64)

    repetitions.times do |repetition|
      benchmark_lanes.rotate(repetition % benchmark_lanes.size).each do |lane|
        result = measure(lane, operations, repetition + 1)
        results << result
        puts "r#{repetition + 1} #{lane.operation}/#{lane.name}: #{result[:operations_per_sec].round.to_i}/s, #{result[:ns_per_operation].round(1)} ns, #{result[:bytes_per_operation].round(1)} B/op"
      end
    end

    summaries = benchmark_lanes.map do |lane|
      samples = results.select { |result| result[:name] == lane.name && result[:operation] == lane.operation }
      middle = samples.size // 2
      {
        name:                       lane.name,
        operation:                  lane.operation,
        median_operations_per_sec:  samples.map(&.[:operations_per_sec]).sort[middle],
        median_ns_per_operation:    samples.map(&.[:ns_per_operation]).sort[middle],
        median_bytes_per_operation: samples.map(&.[:bytes_per_operation]).sort[middle],
      }
    end

    payload = {
      metadata: {
        compiler:            Crystal::DESCRIPTION,
        generated_at_utc:    Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
        operations:          operations,
        warmup_operations:   warmup,
        repetitions:         repetitions,
        payload_fields:      8,
        json_bytes:          JSON_BODY.bytesize,
        msgpack_map_bytes:   MSGPACK_MAP_BODY.size,
        msgpack_array_bytes: MSGPACK_ARRAY_BODY.size,
        specialized_bytes:   FAST_MSGPACK_BODY.size,
        msgpack_version:     MessagePack::VERSION,
        specialized_scope:   "MessagePack map subset used by this typed payload; experimental ceiling, not a general decoder",
      },
      summaries: summaries,
      results:   results,
    }
    File.write(output_path, payload.to_pretty_json)
    puts "Wrote #{output_path}"
  end
end

operations = 100_000
warmup = 10_000
repetitions = 7
output_path = "../results/round22_codec_stock.json"

OptionParser.parse do |parser|
  parser.banner = "Usage: codec_benchmark [options]"
  parser.on("--operations=COUNT", "Operations in each measured lane") { |value| operations = value.to_i }
  parser.on("--warmup=COUNT", "Warmup operations for each lane") { |value| warmup = value.to_i }
  parser.on("--repetitions=COUNT", "Measured repetitions") { |value| repetitions = value.to_i }
  parser.on("--output=PATH", "JSON result path") { |value| output_path = value }
end

Amber::Benchmarks::Codec.run(operations, warmup, repetitions, output_path)
