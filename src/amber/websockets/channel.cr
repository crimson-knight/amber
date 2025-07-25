module Amber
  module WebSockets
    # Sockets subscribe to Channels, where the communication log is handled.  The channel provides functionality
    # to handle socket join `handle_joined` and socket messages `handle_message(msg)`.
    #
    # Example:
    #
    # ```
    # class ChatChannel < Amber::Websockets::Channel
    #   def handle_joined(client_socket)
    #     # functionality when the user joins the channel, optional
    #   end
    #
    #   def handle_leave(client_socket)
    #     # functionality when the user leaves the channel, optional
    #   end
    #
    #   # functionality when a socket sends a message to a channel, required
    #   def handle_message(msg)
    #     rebroadcast!(msg)
    #   end
    # end
    # ```
    abstract class Channel
      @@adapter : Amber::Adapters::PubSubAdapter?
      @@legacy_adapter : WebSockets::Adapters::MemoryAdapter?
      @topic_path : String

      abstract def handle_message(client_socket, msg)

      # Authorization can happen here
      def handle_joined(client_socket, message); end

      def handle_leave(client_socket); end

      def initialize(@topic_path); end

      # Called when a socket subscribes to a channel
      def subscribe_to_channel(client_socket, message)
        handle_joined(client_socket, message)
      end

      # Called when a socket unsubscribes from a channel
      def unsubscribe_from_channel(client_socket)
        handle_leave(client_socket)
      end

      # Called from proc when message is returned from the pubsub service
      # This is a class method that handles message dispatch to instances
      def self.on_message(topic_path : String, client_socket_id : String, message : JSON::Any)
        if client_socket = ClientSockets.client_sockets[client_socket_id]?
          # Create a temporary channel instance to handle the message
          channel = new(topic_path)
          channel.handle_message(client_socket, message)
        end
      end

      # Helper method for retrieving the adapter not nillable
      protected def adapter
        if pubsub_adapter = @@adapter
          pubsub_adapter
        elsif legacy_adapter = @@legacy_adapter
          legacy_adapter
        else
          setup_pubsub_adapter
        end
      end

      # Sends *message* to all subscribing clients belonging to this channel
      # by using the rebroadcast functionality that sends to all subscribers
      def broadcast!(message, topic = @topic_path)
        rebroadcast!(message)
      end

      def rebroadcast!(message, topic = @topic_path)
        case message
        when Hash
          # Use the existing rebroadcast functionality for hash messages
          internal_rebroadcast!(message)
        else
          # For other message types, convert to the expected format
          formatted_message = {
            "event" => "message",
            "topic" => topic,
            "payload" => message
          }
          internal_rebroadcast!(formatted_message)
        end
      end

      # Ensures the pubsub adapter instance exists, and sets up the message callback
      protected def setup_pubsub_adapter
        # Try to get the new adapter-based pub/sub first
        if adapter_based_pubsub = Amber::Server.instance.adapter_based_pubsub
          @@adapter = adapter_based_pubsub
          # Subscribe with a class-level callback
          @@adapter.not_nil!.subscribe(@topic_path) do |sender_id, message|
            # Call the class method to handle message dispatching
            self.class.on_message(@topic_path, sender_id, message)
          end
          @@adapter.not_nil!
        else
          # Fall back to legacy adapter
          @@legacy_adapter = Amber::Server.pubsub_adapter.as(WebSockets::Adapters::MemoryAdapter)
          @@legacy_adapter.not_nil!.on_message(@topic_path, ->(client_socket_id : String, message : JSON::Any) {
            self.class.on_message(@topic_path, client_socket_id, message)
          })
          @@legacy_adapter.not_nil!
        end
      end

      # Sends *message* to the pubsub service
      protected def dispatch(client_socket, message)
        if adapter = @@adapter
          adapter.publish(@topic_path, client_socket.id, message)
        elsif legacy_adapter = @@legacy_adapter
          legacy_adapter.publish(@topic_path, client_socket, message)
        else
          setup_pubsub_adapter
          dispatch(client_socket, message)
        end
      end

      # Rebroadcast this message to all subscribers of the channel
      # example message: {"event" => "message", "topic" => "rooms:123", "subject" => "msg:new", "payload" => {"message" => "hello"}}
      protected def internal_rebroadcast!(message)
        subscribers = ClientSockets.get_subscribers_for_topic(message["topic"])
        subscribers.each_value(&.socket.send(message.to_json))
      end
    end
  end
end
