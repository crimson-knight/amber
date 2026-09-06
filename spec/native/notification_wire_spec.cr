require "spec"
require "../../src/amber/native/notification_wire"

describe Amber::Native::Android::NotificationWire do
  it "encodes version, operation, id and exact UTF-8 lengths" do
    wire = Amber::Native::Android::NotificationWire
    wire.permission.should eq(Bytes[1, 1])
    wire.cancel(Int32::MAX).should eq(Bytes[1, 3, 127, 255, 255, 255])
    notification = Amber::Native::Notification.new(42, "updates", "雪 😀", "")
    packet = wire.post(notification)
    io = IO::Memory.new(packet)
    io.read_byte.should eq(1); io.read_byte.should eq(2)
    io.read_bytes(Int32, IO::ByteFormat::BigEndian).should eq(42)
    {"updates", "雪 😀", ""}.each do |text|
      size = io.read_bytes(Int32, IO::ByteFormat::BigEndian)
      size.should eq(text.bytesize)
      io.read_string(size).should eq(text)
    end
    io.read_byte.should be_nil
  end

  it "bounds the complete packet at 2194 bytes without silently truncated text" do
    notification = Amber::Native::Notification.new(0, "a" * 128, "b" * 1024, "c" * 1024)
    Amber::Native::Android::NotificationWire.post(notification).size.should eq(2194)
  end

  it "rejects invalid fields before registering native work" do
    notifications = [
      Amber::Native::Notification.new(-1, "updates", "Title", ""),
      Amber::Native::Notification.new(1, "bad/channel", "Title", ""),
      Amber::Native::Notification.new(1, "a" * 129, "Title", ""),
      Amber::Native::Notification.new(1, "updates", " \n", ""),
      Amber::Native::Notification.new(1, "updates", "a" * 1025, ""),
      Amber::Native::Notification.new(1, "updates", "Title", "b" * 1025),
      Amber::Native::Notification.new(1, "updates", "Title\0", ""),
      Amber::Native::Notification.new(1, "updates", "Title", String.new(Bytes[255])),
    ]
    notifications.each { |notification| expect_raises(ArgumentError) { Amber::Native::Android::NotificationWire.post(notification) } }
    expect_raises(ArgumentError) { Amber::Native::Android::NotificationWire.cancel(-1) }
  end
end
