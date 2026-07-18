require "option_parser"
require "./application"

module Amber::Benchmarks::DatabaseWorkload
  extend self

  def serve(host : String, port : Int32, route_count : Int32) : Nil
    install_routes(route_count)
    pipeline = Amber::Pipe::Pipeline.new
    pipeline.prepare_pipelines
    server = HTTP::Server.new(pipeline)
    address = server.bind_tcp(host, port)
    Signal::INT.trap { server.close }
    Signal::TERM.trap { server.close }
    puts "READY #{address} database=#{Database::ADAPTER} routes=#{route_count} sqlite_sync=#{Database.sqlite_synchronous}"
    STDOUT.flush
    server.listen
  end
end

host = "127.0.0.1"
port = 8080
route_count = Amber::Benchmarks::DatabaseWorkload::ROUTE_COUNT

OptionParser.parse do |parser|
  parser.banner = "Usage: database_workload [options]"
  parser.on("--host=HOST", "Server bind host") { |value| host = value }
  parser.on("--port=PORT", "Server bind port") { |value| port = value.to_i }
  parser.on("--routes=COUNT", "Installed Amber routes") { |value| route_count = value.to_i }
end

Amber::Benchmarks::DatabaseWorkload.serve(host, port, route_count)
