require "./database"

module Amber::Benchmarks::DatabaseWorkload
  class BenchmarkUser < Grant::Base
    connection benchmark
    table benchmark_users

    column id : Int64, primary: true, auto: false
    column public_id : String
    column email : String
    column password_digest : String
    column display_name : String
    column role : String
    column organization : String
    column created_at_epoch : Int64
  end

  class BenchmarkResource < Grant::Base
    connection benchmark
    table benchmark_resources

    column id : Int64, primary: true, auto: false
    column public_id : String
    column ulid : String
    column user_id : Int64
    column title : String
    column body : String
    column status : String
    column score : Float64
    column version : Int32
    column updated_at_epoch : Int64
  end

  class BenchmarkSession < Grant::Base
    connection benchmark
    table benchmark_sessions

    column token_hash : String, primary: true, auto: false
    column user_id : Int64
    column expires_at_epoch : Int64
    column created_at_epoch : Int64
  end

  class BenchmarkResourceEvent < Grant::Base
    connection benchmark
    table benchmark_resource_events

    column id : Int64, primary: true
    column resource_id : Int64
    column user_id : Int64
    column kind : String
    column value : Int32
    column created_at_epoch : Int64
  end
end
