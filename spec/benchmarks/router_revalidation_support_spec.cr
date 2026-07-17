require "../spec_helper"
require "../../benchmarks/router_revalidation_support"

private def build_profile_router(definitions)
  Amber::Router::RouteSet(Int32).new.tap do |router|
    definitions.each do |definition|
      router.add(definition.trail, definition.payload, definition.constraints)
    end
  end
end

describe Amber::Benchmarks::RouterRevalidation do
  support = Amber::Benchmarks::RouterRevalidation

  it "builds a unique 1,000-route mature application fixture" do
    routes = support.generate_routes(1_000)

    routes.size.should eq 1_000
    routes.map(&.resource).uniq.size.should eq 1_000
    routes.group_by(&.kind).transform_values(&.size).should eq({
      :static      => 450,
      :restful     => 250,
      :variable    => 150,
      :nested      => 50,
      :constrained => 50,
      :glob        => 50,
    })
  end

  it "generates valid integer, UUID, ULID, and slug identifiers" do
    support.identifier(:integer, 42).should match Amber::Benchmarks::RouterRevalidation::INTEGER_CONSTRAINT
    support.identifier(:uuid, 42).should match Amber::Benchmarks::RouterRevalidation::UUID_CONSTRAINT
    support.identifier(:ulid, 42).should match Amber::Benchmarks::RouterRevalidation::ULID_CONSTRAINT
    support.identifier(:slug, 42).should eq "customer-order-42-spring-catalog"
  end

  it "keeps legacy and optimized results equivalent for every traffic profile" do
    definitions = support.generate_routes(1_000)
    router = build_profile_router(definitions)

    Amber::Benchmarks::RouterRevalidation::TRAFFIC_PROFILES.each do |profile|
      traffic = support.generate_profile_traffic(definitions, profile, 256)
      traffic.each do |request|
        legacy = router.find("get#{request.resource}")
        optimized = router.find_span("get", request.resource)

        optimized.found?.should eq legacy.found?
        optimized.payload?.should eq legacy.payload?
        optimized.params.should eq legacy.params
      end
    end
  end

  it "applies each constrained identifier pattern instead of treating it as a generic parameter" do
    definitions = support.generate_routes(1_000)
    router = build_profile_router(definitions)

    [:integer, :uuid, :ulid].each do |style|
      definition = definitions.find { |route| route.kind == :constrained && route.constraint_style == style }.not_nil!
      valid = definition.matching_resource(42)
      invalid_style = style == :integer ? :uuid : :integer
      invalid = definition.matching_resource(42, invalid_style)

      router.find_span("get", valid).found?.should be_true
      router.find_span("get", invalid).found?.should be_false
    end
  end
end
