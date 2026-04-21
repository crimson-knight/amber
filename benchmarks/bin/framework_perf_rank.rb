#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

path = ARGV[0] || "benchmarks/results/framework_performance_lab_latest.json"
payload = JSON.parse(File.read(path))

comparisons = payload.fetch("summary").fetch("comparisons")
metadata = payload.fetch("metadata")

puts "Amber Framework Performance Lab Ranking"
puts "Compiler: #{metadata["compiler"]}"
puts "Crystal: #{metadata["crystal_version"]}"
puts "Generated: #{metadata["generated_at_utc"]}"
puts

comparisons.sort_by { |row| row.fetch("ips_ratio") }.each do |row|
  ratio = row.fetch("ips_ratio")
  slower_factor = row.fetch("slower_factor")
  memory_ratio = row.fetch("memory_ratio")

  puts "#{row.fetch("label")}"
  puts "  throughput ratio: #{format("%.3fx", ratio)}"
  puts "  slower factor:    #{format("%.3fx", slower_factor)}"
  puts "  memory ratio:     #{format("%.3fx", memory_ratio)}"
end
