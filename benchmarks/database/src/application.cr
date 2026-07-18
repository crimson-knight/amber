require "crypto/bcrypt/password"
require "digest/sha256"
require "json"
require "random/secure"
require "../../../src/amber"
require "../../router_revalidation_support"
require "./models"

module Amber::Benchmarks::DatabaseWorkload
  extend self

  alias RouteDefinition = RouterRevalidation::RouteDefinition

  CONTENT_JSON       = "application/json; charset=utf-8"
  SESSION_LIFETIME   = 24.hours.total_seconds.to_i64
  ROUTE_COUNT        = 1_000
  APPLICATION_ROUTES =     9

  ID_CONSTRAINT   = /\A[0-9]+\z/
  UUID_CONSTRAINT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  ULID_CONSTRAINT = /\A[0-9A-HJKMNP-TV-Z]{26}\z/

  class LoginPayload
    include JSON::Serializable

    getter email : String
    getter password : String
  end

  class UpdatePayload
    include JSON::Serializable

    getter status : String
    getter score : Float64
  end

  class Controller < Amber::Controller::Base
    def health : Nil
      resource = BenchmarkResource.find(1_i64)
      if resource
        respond_json(String.build do |io|
          io << %({"status":"ok","database":)
          Database::ADAPTER.to_json(io)
          io << %(,"resource_id":) << resource.id.not_nil! << '}'
        end)
      else
        respond_error(503, "seed data is unavailable")
      end
    end

    def login : Nil
      with_errors do
        payload = LoginPayload.from_json(request.body.not_nil!)
        user = BenchmarkUser.find_by(email: payload.email)
        unless user && Crypto::Bcrypt::Password.new(user.password_digest).verify(payload.password)
          respond_error(401, "invalid credentials")
          next
        end

        raw_token = Random::Secure.hex(32)
        now = Time.utc.to_unix
        user_id = user.id.not_nil!
        BenchmarkSession.create!(
          token_hash: token_hash(raw_token),
          user_id: user_id,
          expires_at_epoch: now + SESSION_LIFETIME,
          created_at_epoch: now
        )

        respond_json(String.build(160) do |io|
          io << %({"token":)
          raw_token.to_json(io)
          io << %(,"user_id":) << user_id
          io << %(,"expires_at_epoch":) << now + SESSION_LIFETIME << '}'
        end)
      end
    end

    def show_by_id : Nil
      with_session do |_session|
        resource = BenchmarkResource.find(params["id"].to_i64)
        resource ? respond_resource(resource) : respond_error(404, "resource not found")
      end
    end

    def show_by_uuid : Nil
      with_session do |_session|
        resource = BenchmarkResource.find_by(public_id: params["uuid"])
        resource ? respond_resource(resource) : respond_error(404, "resource not found")
      end
    end

    def show_by_ulid : Nil
      with_session do |_session|
        resource = BenchmarkResource.find_by(ulid: params["ulid"])
        resource ? respond_resource(resource) : respond_error(404, "resource not found")
      end
    end

    def list_for_user : Nil
      with_session do |_session|
        user_id = params["user_id"].to_i64
        resources = BenchmarkResource.where(user_id: user_id).order(id: :desc).limit(20).select
        respond_json(String.build(5_500) do |io|
          io << %({"user_id":) << user_id << %(,"resources":[)
          resources.each_with_index do |resource, index|
            io << ',' unless index.zero?
            append_resource_json(io, resource)
          end
          io << "]}"
        end)
      end
    end

    def calculate : Nil
      with_session do |_session|
        resource = BenchmarkResource.find(params["id"].to_i64)
        unless resource
          respond_error(404, "resource not found")
          next
        end

        digest = Digest::SHA256.hexdigest do |digest_io|
          digest_io << resource.public_id << ":" << resource.version.to_s << ":"
          digest_io << resource.body << ":" << resource.score.to_s
        end
        resource_id = resource.id.not_nil!
        weighted_score = ((resource.score * 1_000).to_i64 ^ resource_id) & 0x7fff_ffff
        respond_json(String.build(160) do |io|
          io << %({"id":) << resource_id << %(,"digest":)
          digest.to_json(io)
          io << %(,"weighted_score":) << weighted_score << '}'
        end)
      end
    end

    def update : Nil
      with_session do |_session|
        payload = UpdatePayload.from_json(request.body.not_nil!)
        resource = BenchmarkResource.find(params["id"].to_i64)
        unless resource
          respond_error(404, "resource not found")
          next
        end

        resource.update!(
          status: payload.status,
          score: payload.score,
          version: resource.version + 1,
          updated_at_epoch: Time.utc.to_unix
        )
        respond_resource(resource)
      end
    end

    def crud_cycle : Nil
      with_session do |session|
        resource_id = params["id"].to_i64
        return respond_error(404, "resource not found") unless BenchmarkResource.exists?(resource_id)

        now = Time.utc.to_unix
        created = BenchmarkResourceEvent.create!(
          resource_id: resource_id,
          user_id: session.user_id,
          kind: "benchmark-cycle",
          value: 1,
          created_at_epoch: now
        )
        event_id = created.id.not_nil!
        loaded = BenchmarkResourceEvent.find!(event_id)
        loaded.update!(value: loaded.value + 1)
        updated = BenchmarkResourceEvent.find!(event_id)
        value = updated.value
        updated.destroy!

        respond_json(%({"resource_id":#{resource_id},"event_id":#{event_id},"value":#{value},"deleted":true}))
      end
    end

    def filler : Nil
      respond_json(%({"status":"filler"}))
    end

    private def with_errors(&) : Nil
      yield
    rescue ex : JSON::SerializableError | JSON::ParseException
      respond_error(422, "invalid JSON payload")
    rescue ex : DB::Error | Grant::RecordNotSaved | Grant::RecordNotDestroyed
      Log.error(exception: ex) { "Database benchmark request failed" }
      respond_error(500, "database operation failed")
    rescue ex
      Log.error(exception: ex) { "Database benchmark request failed unexpectedly" }
      respond_error(500, "request failed")
    end

    private def with_session(&block : BenchmarkSession ->) : Nil
      with_errors do
        header = request.headers["Authorization"]?
        unless header && header.starts_with?("Bearer ")
          respond_error(401, "missing bearer token")
          next
        end

        raw_token = header.byte_slice(7, header.bytesize - 7)
        session = BenchmarkSession.find(token_hash(raw_token))
        unless session && session.expires_at_epoch > Time.utc.to_unix
          respond_error(401, "invalid session")
          next
        end

        yield session
      end
    end

    private def token_hash(token : String) : String
      Digest::SHA256.hexdigest(token)
    end

    private def respond_resource(resource : BenchmarkResource) : Nil
      respond_json(String.build(520) { |io| append_resource_json(io, resource) })
    end

    private def append_resource_json(io : IO, resource : BenchmarkResource) : Nil
      io << %({"id":) << resource.id.not_nil! << %(,"public_id":)
      resource.public_id.to_json(io)
      io << %(,"ulid":)
      resource.ulid.to_json(io)
      io << %(,"user_id":) << resource.user_id << %(,"title":)
      resource.title.to_json(io)
      io << %(,"body":)
      resource.body.to_json(io)
      io << %(,"status":)
      resource.status.to_json(io)
      io << %(,"score":) << resource.score
      io << %(,"version":) << resource.version
      io << %(,"updated_at_epoch":) << resource.updated_at_epoch << '}'
    end

    private def respond_error(status : Int32, message : String) : Nil
      respond_json(String.build(96) do |io|
        io << %({"error":)
        message.to_json(io)
        io << '}'
      end, status)
    end

    private def respond_json(body : String, status = 200) : Nil
      set_response(body, status, CONTENT_JSON)
    end
  end

  def install_routes(route_count = ROUTE_COUNT) : Nil
    raise ArgumentError.new("route count must be at least #{APPLICATION_ROUTES}") if route_count < APPLICATION_ROUTES

    add_route("GET", "/benchmark/health", :health, ->(controller : Controller) { controller.health })
    add_route("POST", "/api/v1/sessions", :login, ->(controller : Controller) { controller.login })
    add_route("GET", "/api/v1/resources/:id", :show_by_id, ->(controller : Controller) { controller.show_by_id }, {"id" => ID_CONSTRAINT})
    add_route("GET", "/api/v1/resources/by-uuid/:uuid", :show_by_uuid, ->(controller : Controller) { controller.show_by_uuid }, {"uuid" => UUID_CONSTRAINT})
    add_route("GET", "/api/v1/resources/by-ulid/:ulid", :show_by_ulid, ->(controller : Controller) { controller.show_by_ulid }, {"ulid" => ULID_CONSTRAINT})
    add_route("GET", "/api/v1/users/:user_id/resources", :list_for_user, ->(controller : Controller) { controller.list_for_user }, {"user_id" => ID_CONSTRAINT})
    add_route("POST", "/api/v1/resources/:id/calculate", :calculate, ->(controller : Controller) { controller.calculate }, {"id" => ID_CONSTRAINT})
    add_route("PATCH", "/api/v1/resources/:id", :update, ->(controller : Controller) { controller.update }, {"id" => ID_CONSTRAINT})
    add_route("POST", "/api/v1/resources/:id/crud-cycle", :crud_cycle, ->(controller : Controller) { controller.crud_cycle }, {"id" => ID_CONSTRAINT})

    filler_handler = ->(context : HTTP::Server::Context) { Controller.new(context).filler }
    methods = ["GET", "POST", "PUT", "PATCH", "DELETE"]
    RouterRevalidation.generate_routes(route_count - APPLICATION_ROUTES).each_with_index do |definition, index|
      method = methods[index % methods.size]
      Amber::Server.router.add(Amber::Route.new(
        method,
        "/benchmark/filler/#{index}#{definition.resource}",
        filler_handler,
        :filler,
        :web,
        Amber::Router::Scope.new,
        "Amber::Benchmarks::DatabaseWorkload::Controller",
        definition.constraints
      ))
    end
  end

  private def add_route(
    method : String,
    resource : String,
    action : Symbol,
    handler : Controller ->,
    constraints = {} of String => Regex,
  ) : Nil
    Amber::Server.router.add(Amber::Route.new(
      method,
      resource,
      ->(context : HTTP::Server::Context) { handler.call(Controller.new(context)) },
      action,
      :web,
      Amber::Router::Scope.new,
      "Amber::Benchmarks::DatabaseWorkload::Controller",
      constraints
    ))
  end
end
