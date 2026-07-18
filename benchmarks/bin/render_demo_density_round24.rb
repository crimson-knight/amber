#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "json"
require "optparse"

ROOT_DIR = File.expand_path("../..", __dir__)
options = {
  input: File.join(ROOT_DIR, "benchmarks", "results", "round24_digitalocean_demo_density.json"),
  markdown: File.join(ROOT_DIR, "benchmarks", "results", "round24_demo_density_report.md"),
  svg: File.join(ROOT_DIR, "benchmarks", "results", "round24_demo_density_overview.svg"),
}
OptionParser.new do |parser|
  parser.on("--input=PATH", "Round 24 result JSON") { |value| options[:input] = File.expand_path(value) }
  parser.on("--markdown=PATH", "Generated Markdown report") { |value| options[:markdown] = File.expand_path(value) }
  parser.on("--svg=PATH", "Generated SVG overview") { |value| options[:svg] = File.expand_path(value) }
end.parse!

abort "Result not found: #{options[:input]}" unless File.file?(options[:input])
payload = JSON.parse(File.read(options[:input]))
summary = payload.fetch("summary")
abort "Result has no capacity summary" if summary.empty?

labels = payload.dig("metadata", "targets").map { |target| target.fetch("label") }
display_name = {
  "micro" => "$4 micro shared",
  "shared2x4" => "2 vCPU / 4 GB shared",
  "dedicated2x4" => "2 vCPU / 4 GB dedicated",
}
colors = {
  "micro" => "#D89720",
  "shared2x4" => "#1D7874",
  "dedicated2x4" => "#C55336",
}

markdown = []
markdown << "# Amber demo density: shared versus dedicated CPU"
markdown << ""
markdown << "Generated from `#{File.basename(options[:input])}`. A healthy app passes both the 2 RPS steady and 10 RPS burst phases in every repetition."
markdown << ""
markdown << "| Host | CPU class | Monthly price | Healthy apps | Cost / app / month |"
markdown << "| --- | --- | ---: | ---: | ---: |"
labels.each do |label|
  row = summary.fetch(label)
  cost = row.fetch("monthly_cost_per_healthy_app")
  markdown << format(
    "| %s | %s | $%.2f | %d | %s |",
    display_name.fetch(label, label),
    row.fetch("cpu_class"),
    row.fetch("price_monthly"),
    row.fetch("highest_healthy_density"),
    cost ? format("$%.2f", cost) : "n/a"
  )
end

markdown << ""
markdown << "## Density evidence"
labels.each do |label|
  markdown << ""
  markdown << "### #{display_name.fetch(label, label)}"
  markdown << ""
  markdown << "| Apps | Result | Steady RPS / p99 | Burst RPS / p99 | Steal |"
  markdown << "| ---: | --- | ---: | ---: | ---: |"
  summary.fetch(label).fetch("densities").each do |density, row|
    steady = row.dig("phases", "steady") || {}
    burst = row.dig("phases", "burst") || {}
    steady_rps = steady.dig("requests_per_second", "median")
    burst_rps = burst.dig("requests_per_second", "median")
    steady_p99 = steady.dig("p99_seconds", "median")
    burst_p99 = burst.dig("p99_seconds", "median")
    steals = [steady.dig("cpu_steal_fraction", "median"), burst.dig("cpu_steal_fraction", "median")].compact
    markdown << format(
      "| %d | %s | %s | %s | %s |",
      density,
      row.fetch("passed") ? "PASS" : "FAIL: #{row.fetch('failure_reasons').join(', ')}",
      steady_rps ? format("%.1f / %.1f ms", steady_rps, steady_p99 * 1_000) : "n/a",
      burst_rps ? format("%.1f / %.1f ms", burst_rps, burst_p99 * 1_000) : "n/a",
      steals.empty? ? "n/a" : format("%.2f%%", steals.max * 100)
    )
  end
end

markdown << ""
markdown << "The load-generator Droplet is excluded from production cost per app. CPU steal is reported rather than used as a pass/fail gate so the shared-CPU variance remains visible."
File.write(options[:markdown], markdown.join("\n") + "\n")

width = 1_200
height = 680
panel_width = 520
left_x = 90
right_x = 650
top = 170
bar_height = 54
bar_gap = 42
max_density = [labels.map { |label| summary.fetch(label).fetch("highest_healthy_density") }.max, 1].max
cost_values = labels.map { |label| summary.fetch(label).fetch("monthly_cost_per_healthy_app") }.compact
max_cost = [cost_values.max || 1.0, 1.0].max

svg = []
svg << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">)
svg << %(<rect width="#{width}" height="#{height}" fill="#F5F0E6"/>)
svg << %(<path d="M0 0H1200V18H0Z" fill="#173F3A"/>)
svg << %(<text x="60" y="78" font-family="Georgia,serif" font-size="36" font-weight="700" fill="#173F3A">Amber demo density economics</text>)
svg << %(<text x="60" y="116" font-family="Avenir Next,Helvetica,sans-serif" font-size="18" fill="#51625F">One million-row SQLite FULL database and realistic mixed traffic per application</text>)
svg << %(<text x="#{left_x}" y="#{top - 34}" font-family="Avenir Next,Helvetica,sans-serif" font-size="20" font-weight="700" fill="#173F3A">Highest healthy app count</text>)
svg << %(<text x="#{right_x}" y="#{top - 34}" font-family="Avenir Next,Helvetica,sans-serif" font-size="20" font-weight="700" fill="#173F3A">Monthly host cost per healthy app</text>)

labels.each_with_index do |label, index|
  row = summary.fetch(label)
  y = top + index * (bar_height + bar_gap)
  density = row.fetch("highest_healthy_density")
  cost = row.fetch("monthly_cost_per_healthy_app")
  color = colors.fetch(label, "#486A66")
  name = CGI.escapeHTML(display_name.fetch(label, label))
  density_width = density / max_density.to_f * panel_width
  cost_width = cost ? cost / max_cost * panel_width : 0
  svg << %(<text x="#{left_x}" y="#{y - 10}" font-family="Avenir Next,Helvetica,sans-serif" font-size="15" fill="#354744">#{name}</text>)
  svg << %(<rect x="#{left_x}" y="#{y}" width="#{panel_width}" height="#{bar_height}" rx="8" fill="#E3DDD1"/>)
  svg << %(<rect x="#{left_x}" y="#{y}" width="#{density_width.round(1)}" height="#{bar_height}" rx="8" fill="#{color}"/>)
  svg << %(<text x="#{left_x + 16}" y="#{y + 35}" font-family="Avenir Next,Helvetica,sans-serif" font-size="22" font-weight="700" fill="#FFFFFF">#{density} apps</text>)

  svg << %(<text x="#{right_x}" y="#{y - 10}" font-family="Avenir Next,Helvetica,sans-serif" font-size="15" fill="#354744">#{name}</text>)
  svg << %(<rect x="#{right_x}" y="#{y}" width="#{panel_width}" height="#{bar_height}" rx="8" fill="#E3DDD1"/>)
  svg << %(<rect x="#{right_x}" y="#{y}" width="#{cost_width.round(1)}" height="#{bar_height}" rx="8" fill="#{color}"/>) if cost
  svg << %(<text x="#{right_x + 16}" y="#{y + 35}" font-family="Avenir Next,Helvetica,sans-serif" font-size="22" font-weight="700" fill="#{cost_width > 145 ? '#FFFFFF' : '#173F3A'}">#{cost ? format('$%.2f', cost) : 'n/a'}</text>)
end

svg << %(<line x1="60" y1="520" x2="1140" y2="520" stroke="#C9C0B1" stroke-width="1"/>)
svg << %(<text x="60" y="560" font-family="Avenir Next,Helvetica,sans-serif" font-size="16" fill="#51625F">PASS requires zero errors, at least 95% offered load, bounded p99, fair service, no OOM/swap, and 5% free memory.</text>)
svg << %(<text x="60" y="594" font-family="Avenir Next,Helvetica,sans-serif" font-size="16" fill="#51625F">Lower cost per app is better. Dedicated CPU is evaluated for predictability as well as raw density.</text>)
svg << %(<text x="60" y="640" font-family="Georgia,serif" font-size="16" font-style="italic" fill="#173F3A">Amber V2 performance research, Round 24</text>)
svg << %(</svg>)
File.write(options[:svg], svg.join("\n") + "\n")

puts "Wrote #{options[:markdown]} and #{options[:svg]}"
