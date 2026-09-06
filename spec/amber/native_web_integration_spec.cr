require "../spec_helper"
require "../../examples/hybrid_counter/web_controller"

describe "hybrid shared application rules through an Amber web controller" do
  it "shares validation and state between HTTP actions" do
    context = create_context(HTTP::Request.new("POST", "/counter/name?name=Amber"))
    controller = HybridCounter::Controller.new(context)
    JSON.parse(controller.rename)["name"].as_s.should eq("Amber")
    controller.response.status_code.should eq(200)

    count = JSON.parse(controller.show)["count"].as_i
    JSON.parse(controller.increment)["count"].as_i.should eq(count + 1)

    invalid_context = create_context(HTTP::Request.new("POST", "/counter/name?name=x"))
    invalid_controller = HybridCounter::Controller.new(invalid_context)
    JSON.parse(invalid_controller.rename)["name"].as_s.should eq("Amber")
    invalid_controller.response.status_code.should eq(422)
    invalid_controller.response.content_type.should eq("application/json")
  end

  it "keeps the multipart validator compatibility alias" do
    data = JSON.parse(%({"filename":"photo.png","size":100}))
    options = JSON.parse(%({"max_size":10})).as_h
    Amber::Schema::Parser::FileUploadValidator.validate_file("photo", data, options).map(&.code).should eq(["file_too_large"])
  end
end
