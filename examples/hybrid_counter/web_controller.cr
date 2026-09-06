require "../../src/amber"
require "./shared"

module HybridCounter
  class Controller < Amber::Controller::Base
    @@state = State.new

    def show
      response.content_type = "application/json"
      @@state.snapshot
    end

    def increment
      @@state.increment
      show
    end

    def rename
      result = @@state.rename(params["name"]? || "")
      response.status_code = result.success? ? 200 : 422
      show
    end
  end
end
