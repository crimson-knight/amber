require "../../spec_helper"
require "json"

module Amber
  module Pipe
    describe Flash do
      it "leaves the session untouched when a request carries and sets no message" do
        context = create_context(HTTP::Request.new("GET", "/pets/1"))
        flash_pipe = Flash.new
        flash_pipe.next = ->(ctx : HTTP::Server::Context) { }

        flash_pipe.call(context)

        context.session.changed?.should be_falsey
        context.session.has_key?(Flash::PARAM_KEY).should be_false
      end

      it "stores a message set during the request" do
        context = create_context(HTTP::Request.new("POST", "/pets"))
        flash_pipe = Flash.new
        flash_pipe.next = ->(ctx : HTTP::Server::Context) { ctx.flash[:notice] = "Pet saved."; nil }

        flash_pipe.call(context)

        context.session.changed?.should be_true
        Router::Flash::FlashStore.from_session(context.session[Flash::PARAM_KEY].to_s)[:notice].should eq "Pet saved."
      end

      it "clears a message once it has been read" do
        context = create_context(HTTP::Request.new("GET", "/pets"))
        context.session[Flash::PARAM_KEY] = {"notice" => "Pet saved."}.to_json
        flash_pipe = Flash.new
        flash_pipe.next = ->(ctx : HTTP::Server::Context) { ctx.flash.fetch(:notice); nil }

        flash_pipe.call(context)

        context.session.has_key?(Flash::PARAM_KEY).should be_false
      end

      it "sends no session cookie for a request without messages" do
        context = create_context(HTTP::Request.new("GET", "/pets/1"))
        flash_pipe = Flash.new
        flash_pipe.next = ->(ctx : HTTP::Server::Context) { }
        session_pipe = Session.new
        session_pipe.next = flash_pipe

        session_pipe.call(context)

        context.response.headers.has_key?("Set-Cookie").should be_false
      end
    end
  end

  module Router
    describe Flash::FlashStore do
      describe ".from_session" do
        it "creates a flash store from json" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store.has_key?("some_key").should be_true
          flash_store["some_key"].should eq "some_value"
        end

        it "returns an empty flash store if json is invalid" do
          json = "some_key=some_value"
          flash_store = Flash::FlashStore.from_session json

          flash_store.has_key?("some_key").should be_false
        end
      end

      describe "#fetch" do
        it "returns the value" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store.fetch("some_key").should eq "some_value"
        end

        it "supports symbols" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store.fetch(:some_key).should eq "some_value"
        end

        it "returns the default value" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store.fetch(:some_other_key, "default").should eq "default"
        end

        it "marks the value as read" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json
          flash_store.fetch("some_key")
          flash_store = Flash::FlashStore.from_session flash_store.to_session

          flash_store.has_key?("some_key").should be_false
        end

        it "marks the value as read for default value implementation" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json
          flash_store.fetch("some_key", nil)
          flash_store = Flash::FlashStore.from_session flash_store.to_session

          flash_store.has_key?("some_key").should be_false
        end
      end

      describe "#each" do
        it "returns the list of key/value pairs" do
          flashes = {"some_key" => "some_value", "other_key" => "other_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json
          test = Hash(String, String).new
          flash_store.each { |k, v| test[k] = v }
          test.size.should eq 2
        end

        it "marks the keys as read" do
          flashes = {"some_key" => "some_value", "other_key" => "other_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json
          test = Hash(String, String).new
          flash_store.each { |k, v| test[k] = v }
          flash_store = Flash::FlashStore.from_session flash_store.to_session

          flash_store.has_key?("some_key").should be_false
        end
      end

      describe "#now" do
        it "does not keep key even if never read" do
          flash_store = Flash::FlashStore.new
          flash_store.now("some_key", "some_value")
          flash_store = Flash::FlashStore.from_session flash_store.to_session
          flash_store.has_key?("some_key").should be_false
        end
      end

      describe "#keep" do
        it "keeps the key after being read" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json
          flash_store.fetch("some_key")
          flash_store.keep("some_key")
          flash_store = Flash::FlashStore.from_session flash_store.to_session

          flash_store.has_key?("some_key").should be_true
        end
      end

      describe "<< Hash" do
        it "supports [] with String" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store["some_key"].should eq "some_value"
        end

        it "supports [] with Symbol" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store[:some_key].should eq "some_value"
        end

        it "supports []= with String" do
          flash_store = Flash::FlashStore.new
          flash_store["some_key"] = "some_value"

          flash_store["some_key"].should eq "some_value"
        end

        it "supports []= with Symbol" do
          flash_store = Flash::FlashStore.new
          flash_store[:some_key] = "some_value"

          flash_store[:some_key].should eq "some_value"
        end

        it "supports []= with Symbol but reading with String" do
          flash_store = Flash::FlashStore.new
          flash_store[:some_key] = "some_value"

          flash_store["some_key"].should eq "some_value"
        end

        it "supports []? with Symbol" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store[:some_other_key]?.should eq nil
          flash_store[:some_key]?.should eq "some_value"
        end

        it "supports []? with String" do
          flashes = {"some_key" => "some_value"}
          json = flashes.to_json
          flash_store = Flash::FlashStore.from_session json

          flash_store["some_other_key"]?.should eq nil
          flash_store["some_key"]?.should eq "some_value"
        end
      end
    end
  end
end
