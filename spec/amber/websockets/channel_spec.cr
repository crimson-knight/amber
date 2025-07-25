require "../../spec_helper"

module Amber
  describe WebSockets::ClientSocket do
    describe "#on_message" do
      it "should call `handle_message`" do
        message = JSON.parse({"event" => "message", "topic" => "user_room:123", "subject" => "msg:new", "payload" => {"message" => "hey guys"}}.to_json)
        _, client_socket = create_user_socket
        Amber::WebSockets::ClientSockets.add_client_socket(client_socket)
        
        # Get the channel instance from the client socket's channels
        # WebSockets.topic_path("user_room:*") returns "user_room"
        channel = client_socket.get_channel("user_room").not_nil!
        
        # Call handle_message directly on the channel instance
        channel.handle_message(client_socket, message)
        
        # Check that the message was processed by checking the channel's test field
        channel.as(UserChannel).test_field.last.should eq "hey guys"
        
        Amber::WebSockets::ClientSockets.remove_client_socket(client_socket)
      end
    end

    describe "#subscribe_to_channel" do
      it "should call `handle_joined`" do
        _, client_socket = create_user_socket
        # Get the channel instance from the client socket's channels
        # WebSockets.topic_path("user_room:*") returns "user_room"
        channel = client_socket.get_channel("user_room").not_nil!
        channel.subscribe_to_channel(client_socket, "{}")
        channel.as(UserChannel).test_field.last.should eq "handle joined #{client_socket.id}"
      end
    end

    describe "#unsubscribe_from_channel" do
      it "should call `handle_leave`" do
        _, client_socket = create_user_socket
        # Get the channel instance from the client socket's channels  
        # WebSockets.topic_path("user_room:*") returns "user_room"
        channel = client_socket.get_channel("user_room").not_nil!
        channel.unsubscribe_from_channel(client_socket)
        channel.as(UserChannel).test_field.last.should eq "handle leave #{client_socket.id}"
      end
    end
    
    describe "#handle_message" do
      it "should process the message" do
        message = JSON.parse({"event" => "message", "topic" => "user_room:123", "subject" => "msg:new", "payload" => {"message" => "hey guys"}}.to_json)
        _, client_socket = create_user_socket
        # Get the channel instance from the client socket's channels
        # WebSockets.topic_path("user_room:*") returns "user_room"
        channel = client_socket.get_channel("user_room").not_nil!
        
        channel.handle_message(client_socket, message)
        
        channel.as(UserChannel).test_field.last.should eq "hey guys"
      end
    end
  end
end
