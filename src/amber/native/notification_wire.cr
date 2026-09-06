require "./services"

module Amber::Native::Android::NotificationWire
  def self.permission : Bytes
    Bytes[1, 1]
  end

  def self.cancel(id : Int32) : Bytes
    raise ArgumentError.new("Notification id must be nonnegative") if id < 0
    io = IO::Memory.new
    io.write(Bytes[1, 3])
    io.write_bytes(id, IO::ByteFormat::BigEndian)
    io.to_slice.dup
  end

  def self.post(notification : Amber::Native::Notification) : Bytes
    raise ArgumentError.new("Notification id must be nonnegative") if notification.id < 0
    channel, title, body = notification.channel, notification.title, notification.body
    unless channel.matches?(/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/) && channel.bytesize <= 128
      raise ArgumentError.new("Invalid notification channel")
    end
    { {title, 1024}, {body, 1024} }.each do |text, limit|
      raise ArgumentError.new("Invalid notification text") unless text.valid_encoding? && text.bytesize <= limit && !text.includes?('\0')
    end
    raise ArgumentError.new("Notification title cannot be blank") if title.strip.empty?
    io = IO::Memory.new
    io.write(Bytes[1, 2])
    io.write_bytes(notification.id, IO::ByteFormat::BigEndian)
    {channel, title, body}.each do |text|
      io.write_bytes(text.bytesize, IO::ByteFormat::BigEndian)
      io.write(text.to_slice)
    end
    io.to_slice.dup
  end
end
