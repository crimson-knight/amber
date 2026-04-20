#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

ROOT = File.expand_path("..", __dir__)
RESULTS_DIR = File.join(ROOT, "results")

BASELINE_PATH = File.join(RESULTS_DIR, "baseline_expanded.json")
FINAL_PATH = File.join(RESULTS_DIR, "final_expanded.json")
CRYSTAL_V3_PATH = File.join(RESULTS_DIR, "strategy_compare_crystal_full_v3.json")
ACRYSTAL_V3_PATH = File.join(RESULTS_DIR, "strategy_compare_acrystal_full_v3.json")

LOOKUP_TYPES = %i[fixed variable glob notfound].freeze
HISTORICAL_TIERS = [100, 5000, 10_000].freeze

def format_ratio(ratio)
  format("%.2fx", ratio)
end

def load_historical(path)
  JSON.parse(File.read(path)).each_with_object({}) do |row, index|
    tier = row.fetch("tier").to_i
    index[tier] = {
      fixed: row.fetch("ips_fixed").to_f,
      variable: row.fetch("ips_variable").to_f,
      glob: row.fetch("ips_glob").to_f,
      notfound: row.fetch("ips_notfound").to_f,
      registration_ms: row.fetch("registration_ms").to_f,
    }
  end
end

def load_strategy(path, strategy_key)
  JSON.parse(File.read(path)).fetch("results").each_with_object({}) do |row, index|
    next unless row.fetch("strategy") == strategy_key

    tier = row.fetch("tier").to_i
    index[tier] ||= {}
    index[tier][row.fetch("lookup_type").to_sym] = row.fetch("ips").to_f
    index[tier][:registration_ms] = row.fetch("registration_ms").to_f
  end
end

def print_section(title)
  puts
  puts title
end

def print_table(label, from_rows, to_rows)
  print_section(label)

  HISTORICAL_TIERS.each do |tier|
    next unless from_rows[tier] && to_rows[tier]

    puts "tier #{tier}:"
    LOOKUP_TYPES.each do |lookup_type|
      ratio = to_rows[tier].fetch(lookup_type) / from_rows[tier].fetch(lookup_type)
      puts "  #{lookup_type.to_s.ljust(8)} #{format_ratio(ratio)}"
    end
  end
end

baseline = load_historical(BASELINE_PATH)
internalized = load_historical(FINAL_PATH)
crystal_current = load_strategy(CRYSTAL_V3_PATH, "current_find")
crystal_experimental = load_strategy(CRYSTAL_V3_PATH, "experimental_best")
acrystal_current = load_strategy(ACRYSTAL_V3_PATH, "current_find")
acrystal_experimental = load_strategy(ACRYSTAL_V3_PATH, "experimental_best")

puts "Amber router benchmark reconciliation"
puts "Historical baseline: #{BASELINE_PATH}"
puts "Internalized engine: #{FINAL_PATH}"
puts "Current experiment: #{CRYSTAL_V3_PATH} and #{ACRYSTAL_V3_PATH}"
puts
puts "Note: historical and current experiment files were not recorded in the same"
puts "session, so cumulative comparisons are derived rather than single-run measured."

print_table("Historical measured gains: old amber_router shard -> internalized engine", baseline, internalized)
print_table("Current measured gains: crystal current_find -> crystal experimental_best", crystal_current, crystal_experimental)
print_table("Current measured gains: acrystal current_find -> acrystal experimental_best", acrystal_current, acrystal_experimental)
print_table("Derived cumulative gains: old amber_router shard -> crystal experimental_best", baseline, crystal_experimental)
print_table("Derived cumulative gains: old amber_router shard -> acrystal experimental_best", baseline, acrystal_experimental)
