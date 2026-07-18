#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "socket"
require_relative "demo_density_round24_support"
require_relative "demo_density_fixed_rate"

class DemoDensityFakeServer
  attr_reader :port

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @connections = []
    @mutex = Mutex.new
    @thread = Thread.new { accept_connections }
  end

  def close
    @server.close
    @thread.join(1)
    @mutex.synchronize { @connections.each { |thread| thread.kill if thread.alive? } }
  end

  private

  def accept_connections
    loop do
      socket = @server.accept
      thread = Thread.new(socket) { |connection| serve(connection) }
      @mutex.synchronize { @connections << thread }
    end
  rescue IOError, Errno::EBADF
    nil
  end

  def serve(socket)
    loop do
      request_line = socket.gets
      break unless request_line

      content_length = 0
      while (line = socket.gets)
        break if line == "\r\n"
        content_length = line.split(":", 2).last.to_i if line.downcase.start_with?("content-length:")
      end
      socket.read(content_length) if content_length.positive?
      path = request_line.split.fetch(1)
      body = if path == "/api/v1/sessions"
               JSON.generate("token" => "a" * 64, "user_id" => 1, "expires_at_epoch" => 9_999_999_999)
             else
               JSON.generate("status" => "ok", "resource_id" => 1, "payload" => "test-response")
             end
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: keep-alive\r\n\r\n#{body}")
    end
  rescue IOError, Errno::ECONNRESET, Errno::EPIPE
    nil
  ensure
    socket.close
  end
end

class DemoDensityRound24Test < Minitest::Test
  PHASE = {
    "minimum_attainment" => 0.95,
    "maximum_p99_seconds" => 0.25,
    "minimum_fairness" => 0.95,
    "minimum_memory_available_fraction" => 0.05,
  }.freeze

  def healthy_load
    {
      "overall" => {
        "errors" => 0,
        "attainment" => 0.99,
        "p99_seconds" => 0.12,
        "fairness" => 0.99,
      },
    }
  end

  def healthy_telemetry
    {
      "all_units_active" => true,
      "oom_kills" => 0,
      "swap_in_pages" => 0,
      "swap_out_pages" => 0,
      "swap_total_bytes" => 0,
      "memory_available_fraction" => 0.20,
    }
  end

  def test_healthy_trial_passes
    assert DemoDensityRound24.evaluate_trial(healthy_load, healthy_telemetry, PHASE).fetch("passed")
  end

  def test_proc_meminfo_keys_drop_the_kernel_colon
    parsed = DemoDensityRound24.parse_properties("MemTotal:=1000\nMemAvailable:=250\nstatus=ok\n")

    assert_equal "1000", parsed.fetch("MemTotal")
    assert_equal "250", parsed.fetch("MemAvailable")
    assert_equal "ok", parsed.fetch("status")
  end

  def test_each_capacity_gate_is_enforced
    load = Marshal.load(Marshal.dump(healthy_load))
    load["overall"]["p99_seconds"] = 0.5
    result = DemoDensityRound24.evaluate_trial(load, healthy_telemetry, PHASE)

    refute result.fetch("passed")
    assert_includes result.fetch("failure_reasons"), "p99 latency"
  end

  def test_cost_per_app_uses_highest_passing_density
    payload = {
      "metadata" => {
        "repetitions" => 1,
        "phases" => [{"name" => "steady"}, {"name" => "burst"}],
        "targets" => [{
          "label" => "dedicated",
          "cpu_class" => "dedicated",
          "size" => "c-2",
          "price_monthly" => 42.0,
          "price_hourly" => 0.0625,
        }],
      },
      "trials" => [4, 8].flat_map do |density|
        %w[steady burst].map do |phase|
          {
            "target" => "dedicated",
            "density" => density,
            "phase" => phase,
            "gate" => {"passed" => density == 4, "failure_reasons" => density == 4 ? [] : ["p99 latency"]},
            "load" => {"overall" => {"success_rps" => 1.0, "p99_seconds" => 0.1, "attainment" => 1.0, "fairness" => 1.0}},
            "telemetry" => {"cpu_steal_fraction" => 0.0, "memory_available_bytes" => 1_000},
          }
        end
      end,
    }

    summary = DemoDensityRound24.build_summary(payload).fetch("dedicated")
    assert_equal 4, summary.fetch("highest_healthy_density")
    assert_in_delta 10.5, summary.fetch("monthly_cost_per_healthy_app")
  end

  def test_fixed_rate_generator_exercises_a_complete_http_session
    server = DemoDensityFakeServer.new
    result = DemoDensityFixedRate.run(
      hosts: ["http://127.0.0.1:#{server.port}"],
      rate_per_app: 20.0,
      duration: 0.5,
      warmup: 0.1,
      timeout: 1.0,
      seed: 24_024
    )

    assert_operator result.dig("overall", "attempted"), :>=, 9
    assert_equal 0, result.dig("overall", "errors")
    assert_operator result.dig("overall", "attainment"), :>=, 0.9
  ensure
    server&.close
  end
end
