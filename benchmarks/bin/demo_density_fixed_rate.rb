#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "thread"
require "time"
require "uri"

module DemoDensityFixedRate
  module_function

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def percentile(values, fraction)
    sorted = values.sort
    return 0.0 if sorted.empty?

    sorted[((sorted.length - 1) * fraction).round]
  end

  def fairness(values)
    return 0.0 if values.empty?

    denominator = values.length * values.sum { |value| value**2 }
    denominator.zero? ? 0.0 : values.sum**2 / denominator
  end

  class Client
    PASSWORD = "AmberBenchmark!2026"

    def initialize(base_url, app_index, timeout)
      @base_uri = URI(base_url)
      @app_index = app_index
      @timeout = timeout
      @token = nil
    end

    def run(initial_sequence, interval, warmup, duration)
      metrics = blank_metrics
      sequence = initial_sequence
      http = Net::HTTP.new(@base_uri.host, @base_uri.port)
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http.write_timeout = @timeout if http.respond_to?(:write_timeout=)
      http.keep_alive_timeout = @timeout

      http.start do |connection|
        initial_login!(connection)
        common_start = yield
        sleep(common_start - DemoDensityFixedRate.monotonic) if DemoDensityFixedRate.monotonic < common_start
        measurement_start = common_start + warmup
        finish = measurement_start + duration
        next_request_at = common_start

        while next_request_at < finish
          now = DemoDensityFixedRate.monotonic
          sleep(next_request_at - now) if now < next_request_at
          started = DemoDensityFixedRate.monotonic
          measured = started >= measurement_start
          lag = [started - next_request_at, 0.0].max
          sequence += 1

          begin
            kind, response = perform(connection, sequence)
            latency = DemoDensityFixedRate.monotonic - started
            record(metrics, measured, kind, response, latency, lag, interval)
          rescue StandardError => error
            record_exception(metrics, measured, error, lag, interval)
          end
          next_request_at += interval
        end
      end

      finalize(metrics, duration)
    end

    private

    def blank_metrics
      {
        "attempted" => 0,
        "successes" => 0,
        "errors" => 0,
        "status_counts" => Hash.new(0),
        "kind_counts" => Hash.new(0),
        "latencies" => [],
        "deadline_misses" => 0,
        "max_schedule_lag_seconds" => 0.0,
        "exceptions" => [],
      }
    end

    def initial_login!(connection)
      _kind, response = perform(connection, 100)
      raise "initial login returned HTTP #{response.code}" unless response.code.to_i == 200 && @token
    end

    def perform(connection, sequence)
      kind, request = build_request(sequence)
      response = connection.request(request)
      if kind == "login" && response.code.to_i == 200
        @token = JSON.parse(response.body).fetch("token")
      end
      [kind, response]
    end

    def build_request(sequence)
      bucket = sequence % 100
      return login_request(sequence) if bucket < 2

      id = id_for(sequence)
      if bucket < 47
        ["read_id", request(Net::HTTP::Get, "/api/v1/resources/#{id}")]
      elsif bucket < 62
        uuid = format("10000000-0000-4000-8000-%012x", id)
        ["read_uuid", request(Net::HTTP::Get, "/api/v1/resources/by-uuid/#{uuid}")]
      elsif bucket < 72
        ulid = "01J8Z3M5N7#{format('%016d', id)}"
        ["read_ulid", request(Net::HTTP::Get, "/api/v1/resources/by-ulid/#{ulid}")]
      elsif bucket < 82
        user_id = ((id - 1) % 10_000) + 1
        ["list", request(Net::HTTP::Get, "/api/v1/users/#{user_id}/resources")]
      elsif bucket < 90
        ["calculate", request(Net::HTTP::Post, "/api/v1/resources/#{id}/calculate")]
      elsif bucket < 96
        body = JSON.generate("status" => "active", "score" => (id % 10_000) / 100.0)
        ["update", request(Net::HTTP::Patch, "/api/v1/resources/#{id}", body)]
      else
        ["crud", request(Net::HTTP::Post, "/api/v1/resources/#{id}/crud-cycle")]
      end
    end

    def login_request(sequence)
      user_id = (sequence % 50) + 1
      body = JSON.generate(
        "email" => format("user%06d@example.test", user_id),
        "password" => PASSWORD
      )
      ["login", request(Net::HTTP::Post, "/api/v1/sessions", body, authenticated: false)]
    end

    def request(type, path, body = nil, authenticated: true)
      headers = {"Accept" => "application/json"}
      headers["Authorization"] = "Bearer #{@token}" if authenticated
      headers["Content-Type"] = "application/json" if body
      type.new(path, headers).tap { |request| request.body = body if body }
    end

    def id_for(sequence)
      if sequence % 10 < 7
        ((sequence * 7_919 + @app_index * 101) % 200_000) + 1
      else
        ((sequence * 104_729 + @app_index * 1_009) % 1_000_000) + 1
      end
    end

    def record(metrics, measured, kind, response, latency, lag, interval)
      return unless measured

      status = response.code.to_i
      metrics["attempted"] += 1
      metrics["status_counts"][status.to_s] += 1
      metrics["kind_counts"][kind] += 1
      metrics["latencies"] << latency
      metrics["max_schedule_lag_seconds"] = [metrics["max_schedule_lag_seconds"], lag].max
      metrics["deadline_misses"] += 1 if lag > interval
      if status == 200
        metrics["successes"] += 1
      else
        metrics["errors"] += 1
      end
    end

    def record_exception(metrics, measured, error, lag, interval)
      return unless measured

      metrics["attempted"] += 1
      metrics["errors"] += 1
      metrics["status_counts"]["exception"] += 1
      metrics["max_schedule_lag_seconds"] = [metrics["max_schedule_lag_seconds"], lag].max
      metrics["deadline_misses"] += 1 if lag > interval
      metrics["exceptions"] << "#{error.class}: #{error.message}" if metrics["exceptions"].length < 10
    end

    def finalize(metrics, duration)
      latencies = metrics.delete("latencies")
      metrics.merge(
        "app_index" => @app_index,
        "base_url" => @base_uri.to_s,
        "success_rps" => metrics.fetch("successes") / duration,
        "attempted_rps" => metrics.fetch("attempted") / duration,
        "p50_seconds" => DemoDensityFixedRate.percentile(latencies, 0.5),
        "p95_seconds" => DemoDensityFixedRate.percentile(latencies, 0.95),
        "p99_seconds" => DemoDensityFixedRate.percentile(latencies, 0.99),
        "max_latency_seconds" => latencies.max || 0.0,
        "_latencies" => latencies
      )
    end
  end

  def run(options)
    interval = 1.0 / options.fetch(:rate_per_app)
    state = {"ready" => 0, "failures" => []}
    mutex = Mutex.new
    condition = ConditionVariable.new
    common_start = nil

    threads = options.fetch(:hosts).each_with_index.map do |host, index|
      Thread.new do
        client = Client.new(host, index + 1, options.fetch(:timeout))
        client.run(options.fetch(:seed) + index * 17, interval, options.fetch(:warmup), options.fetch(:duration)) do
          mutex.synchronize do
            state["ready"] += 1
            condition.broadcast
            condition.wait(mutex) until common_start
            common_start
          end
        end
      rescue StandardError => error
        mutex.synchronize do
          state["failures"] << {"app_index" => index + 1, "error" => "#{error.class}: #{error.message}"}
          condition.broadcast
        end
        nil
      end
    end

    mutex.synchronize do
      condition.wait(mutex) while state.fetch("ready") + state.fetch("failures").length < options.fetch(:hosts).length
      common_start = monotonic + 0.5
      condition.broadcast
    end

    per_app = threads.map(&:value).compact
    successes = per_app.sum { |row| row.fetch("successes") }
    attempted = per_app.sum { |row| row.fetch("attempted") }
    errors = per_app.sum { |row| row.fetch("errors") } + state.fetch("failures").length
    success_rates = per_app.map { |row| row.fetch("success_rps") }
    latencies = per_app.flat_map { |row| row.delete("_latencies") }
    target_rps = options.fetch(:rate_per_app) * options.fetch(:hosts).length
    success_rps = successes / options.fetch(:duration)

    {
      "metadata" => {
        "generated_at_utc" => Time.now.utc.iso8601,
        "hosts" => options.fetch(:hosts),
        "rate_per_app" => options.fetch(:rate_per_app),
        "target_total_rps" => target_rps,
        "warmup_seconds" => options.fetch(:warmup),
        "duration_seconds" => options.fetch(:duration),
        "request_timeout_seconds" => options.fetch(:timeout),
        "seed" => options.fetch(:seed),
        "arrival_model" => "one fixed-interval persistent client per demo application",
        "workload" => "2% bcrypt login, 80% indexed reads/lists, 8% SHA-256 calculation, 6% update, 4% CRUD cycle",
      },
      "overall" => {
        "attempted" => attempted,
        "successes" => successes,
        "errors" => errors,
        "success_rps" => success_rps,
        "target_rps" => target_rps,
        "attainment" => target_rps.zero? ? 0.0 : success_rps / target_rps,
        "p50_seconds" => percentile(latencies, 0.5),
        "p95_seconds" => percentile(latencies, 0.95),
        "p99_seconds" => percentile(latencies, 0.99),
        "fairness" => fairness(success_rates),
        "minimum_app_rps" => success_rates.min || 0.0,
        "maximum_app_rps" => success_rates.max || 0.0,
        "deadline_misses" => per_app.sum { |row| row.fetch("deadline_misses") },
        "setup_failures" => state.fetch("failures"),
      },
      "per_app" => per_app,
    }
  end

  def parse_options(argv)
    options = {
      duration: 30.0,
      hosts: [],
      rate_per_app: 2.0,
      seed: 24_024,
      timeout: 5.0,
      warmup: 5.0,
    }
    OptionParser.new do |parser|
      parser.banner = "Usage: demo_density_fixed_rate.rb --hosts=URL,... [options]"
      parser.on("--hosts=LIST", "Comma-separated demo base URLs") { |value| options[:hosts] = value.split(",") }
      parser.on("--rate-per-app=RPS", Float, "Offered requests/sec per app") { |value| options[:rate_per_app] = value }
      parser.on("--duration=SECONDS", Float, "Measured duration") { |value| options[:duration] = value }
      parser.on("--warmup=SECONDS", Float, "Unmeasured warmup") { |value| options[:warmup] = value }
      parser.on("--timeout=SECONDS", Float, "Per-request timeout") { |value| options[:timeout] = value }
      parser.on("--seed=INTEGER", Integer, "Deterministic request sequence seed") { |value| options[:seed] = value }
    end.parse!(argv)

    abort "--hosts is required" if options[:hosts].empty?
    abort "--rate-per-app must be positive" unless options[:rate_per_app].positive?
    abort "--duration must be positive" unless options[:duration].positive?
    abort "--warmup cannot be negative" if options[:warmup].negative?
    options
  end
end

if __FILE__ == $PROGRAM_NAME
  puts JSON.pretty_generate(DemoDensityFixedRate.run(DemoDensityFixedRate.parse_options(ARGV)))
end
