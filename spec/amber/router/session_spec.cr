require "../../spec_helper"
include SessionHelper

module Amber::Router
  describe Session::Store do
    it "keeps sessions in a signed cookie for store signed_cookie" do
      store = Session::Store.new(new_cookie_store, create_session_config("signed_cookie"))

      cookie_session = store.build.as(Session::CookieStore)

      cookie_session.store.should be_a Cookies::SignedStore
    end

    it "keeps sessions in an encrypted cookie for store encrypted_cookie" do
      store = Session::Store.new(new_cookie_store, create_session_config("encrypted_cookie"))

      cookie_session = store.build.as(Session::CookieStore)

      cookie_session.store.should be_a Cookies::EncryptedStore
    end

    it "keeps sessions on the server through the configured adapter for store adapter" do
      store = Session::Store.new(new_cookie_store, create_session_config("adapter"))

      adapter_session = store.build.as(Session::AdapterSessionStore)

      adapter_session.adapter.should be_a Amber::Adapters::MemorySessionAdapter
    end

    it "defaults to a signed cookie" do
      Amber::Configuration::SessionConfig.new.store_type.should eq :signed_cookie
    end
  end

  describe Session::SessionHash do
    it "stays unchanged when deleting a key it does not hold" do
      session_values = Session::SessionHash.new

      session_values.delete("_flash")

      session_values.changed.should be_false
    end

    it "is changed when deleting a key it holds" do
      session_values = Session::SessionHash.new
      session_values["_flash"] = "{\"notice\":\"Saved.\"}"
      session_values.changed = false

      session_values.delete("_flash")

      session_values.changed.should be_true
    end
  end
end
