module Amber
  class Cluster
    @@env_hash : Hash(String, String)?

    def self.env_hash
      @@env_hash ||= begin
        env = ENV.to_h
        env["FORKED"] = "1"
        env["AMBER_ENV"] = Amber.env.to_s
        env
      end
    end

    # Crystal 1.21 made multi-threaded mode unconditional, and Process.fork is
    # unavailable there. Merely REFERENCING it is a compile error, so from 1.21
    # onward every application built on Amber failed to compile — whether or not
    # it ever enabled cluster mode:
    #
    #   Error: Process fork is unsupported with multithreaded mode
    #
    # The old body was fork-then-exec: fork a child and immediately have it run
    # PROGRAM_NAME with FORKED=1 in its environment. Spawning that process
    # directly does the same work with one fewer step, and the only caller
    # discards the return value (`thread_count.times { Cluster.fork }`), so the
    # change of return type is not observable.
    def self.fork
      Process.new(PROGRAM_NAME, nil, env_hash, true, false,
        input: Process::Redirect::Inherit,
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit)
    end

    def self.master?
      (ENV["FORKED"]? || "0") == "0"
    end

    def self.worker?
      (ENV["FORKED"]? || "0") == "1"
    end
  end
end
