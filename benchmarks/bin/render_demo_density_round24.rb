#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "json"
require "optparse"

ROOT_DIR = File.expand_path("../..", __dir__)
options = {
  input: File.join(ROOT_DIR, "benchmarks", "results", "round24_demo_density_final.json"),
  markdown: File.join(ROOT_DIR, "benchmarks", "results", "round24_demo_density_report.md"),
  svg: File.join(ROOT_DIR, "benchmarks", "results", "round24_demo_density_overview.svg"),
}
OptionParser.new do |parser|
  parser.on("--input=PATH", "Synthesized Round 24 result JSON") { |value| options[:input] = File.expand_path(value) }
  parser.on("--markdown=PATH", "Generated Markdown report") { |value| options[:markdown] = File.expand_path(value) }
  parser.on("--svg=PATH", "Generated SVG overview") { |value| options[:svg] = File.expand_path(value) }
end.parse!

abort "Result not found: #{options[:input]}" unless File.file?(options[:input])
payload = JSON.parse(File.read(options[:input]))
plans = payload.fetch("plans")
labels = %w[micro shared2x4 dedicated2x4]
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

shared = plans.fetch("shared2x4")
dedicated = plans.fetch("dedicated2x4")
equal = payload.dig("comparisons", "equal_resource_density_40")
shared_40 = equal.fetch("shared2x4")
dedicated_40 = equal.fetch("dedicated2x4")
burst_reduction = 1.0 - dedicated_40.dig("burst", "p99_milliseconds", "median") / shared_40.dig("burst", "p99_milliseconds", "median")

markdown = []
markdown << "# Amber demo density: shared versus dedicated CPU"
markdown << ""
markdown << "## Bottom line"
markdown << ""
markdown << format(
  "The **$24 shared 2-vCPU / 4-GB Droplet is the cost winner**. It passed at 80 independent Amber apps, or **$%.2f/app/month** at the measured edge. A safer 64-app operating cap leaves 20%% measured headroom and costs **$%.3f/app/month**.",
  shared.fetch("monthly_cost_per_healthy_app"),
  shared.fetch("monthly_cost_per_recommended_app")
)
markdown << ""
markdown << "| Host | Price | Disk | Measured healthy apps | Edge cost / app | Recommended cap | Recommended cost / app | First limit |"
markdown << "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |"
labels.each do |label|
  plan = plans.fetch(label)
  markdown << format(
    "| %s | $%.2f | %d GB | %d | $%.3f | %d | $%.3f | %s at %d apps |",
    display_name.fetch(label),
    plan.fetch("price_monthly"),
    plan.fetch("disk_gb"),
    plan.fetch("healthy_apps"),
    plan.fetch("monthly_cost_per_healthy_app"),
    plan.fetch("recommended_apps"),
    plan.fetch("monthly_cost_per_recommended_app"),
    plan.fetch("limiter"),
    plan.fetch("first_failed_density")
  )
end

markdown << ""
markdown << "## What dedicated buys"
markdown << ""
markdown << format(
  "At the same 40-app density, both equal-vCPU/equal-RAM plans delivered every request. Dedicated CPU reduced median burst p99 by **%.0f%%** and held observed CPU steal effectively at zero, but its 25-GB disk capped this large-data test at 40 apps.",
  burst_reduction * 100
)
markdown << ""
markdown << "| 40-app phase | Shared p99 median / max | Dedicated p99 median / max | Shared steal max | Dedicated steal max |"
markdown << "| --- | ---: | ---: | ---: | ---: |"
%w[steady burst].each do |phase|
  shared_phase = shared_40.fetch(phase)
  dedicated_phase = dedicated_40.fetch(phase)
  markdown << format(
    "| %s | %.1f / %.1f ms | %.1f / %.1f ms | %.2f%% | %.2f%% |",
    phase.capitalize,
    shared_phase.dig("p99_milliseconds", "median"),
    shared_phase.dig("p99_milliseconds", "max"),
    dedicated_phase.dig("p99_milliseconds", "median"),
    dedicated_phase.dig("p99_milliseconds", "max"),
    shared_phase.dig("cpu_steal_percent", "max"),
    dedicated_phase.dig("cpu_steal_percent", "max")
  )
end

markdown << ""
markdown << "## Boundary quality"
markdown << ""
markdown << "| Host | Apps | Steady p99 median / max | Burst p99 median / max | Burst CPU max | Steal max | Free memory min |"
markdown << "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"
labels.each do |label|
  plan = plans.fetch(label)
  steady = plan.dig("boundary_metrics", "steady")
  burst = plan.dig("boundary_metrics", "burst")
  markdown << format(
    "| %s | %d | %.1f / %.1f ms | %.1f / %.1f ms | %.1f%% | %.2f%% | %.0f MiB |",
    display_name.fetch(label),
    plan.fetch("healthy_apps"),
    steady.dig("p99_milliseconds", "median"),
    steady.dig("p99_milliseconds", "max"),
    burst.dig("p99_milliseconds", "median"),
    burst.dig("p99_milliseconds", "max"),
    burst.dig("target_cpu_percent", "max"),
    [steady.dig("cpu_steal_percent", "max"), burst.dig("cpu_steal_percent", "max")].max,
    burst.dig("memory_available_mebibytes", "min")
  )
end

markdown << ""
markdown << "## Deployment choice"
markdown << ""
markdown << "- **Best cost per app:** run up to 64 demos on `s-2vcpu-4gb` shared CPU for $0.375/app/month and retain 20% measured density headroom."
markdown << "- **Lowest total bill:** run up to 8 demos on `s-1vcpu-512mb-10gb` for $0.50/app/month; its measured edge was 10 and disk, not compute, stopped density 12."
markdown << "- **Best predictability:** run up to 32 demos on `c-2` dedicated CPU for $1.313/app/month; its measured edge was 40 and disk, not compute, stopped density 44."
markdown << ""
markdown << "## Validation"
markdown << ""
markdown << format(
  "The synthesis contains **%d capacity trials plus %d smoke trials**, with **%d cloned databases checked**, %d integrity failures, %d request errors, and %d OOM kills. Each app had 1,000 routes, 10,000 users, one million resources, and a private 483,098,624-byte SQLite FULL database.",
  payload.dig("metadata", "capacity_trial_count"),
  payload.dig("metadata", "smoke_trial_count"),
  payload.dig("metadata", "integrity_databases_checked"),
  payload.dig("metadata", "integrity_failures"),
  payload.dig("metadata", "request_errors"),
  payload.dig("metadata", "oom_kills")
)
markdown << ""
markdown << "The shared host passed all three 80-app repetitions. At 84 apps, one of three bursts crossed the 1-second p99 gate while all requests still completed, establishing a latency-variance boundary rather than a crash boundary. Costs exclude the temporary load generator."
File.write(options[:markdown], markdown.join("\n") + "\n")

width = 1_200
height = 760
panel_width = 500
left_x = 80
right_x = 650
top = 190
bar_height = 62
bar_gap = 54
max_capacity = plans.values.map { |plan| plan.fetch("healthy_apps") }.max.to_f
max_recommended_cost = plans.values.map { |plan| plan.fetch("monthly_cost_per_recommended_app") }.max

svg = []
svg << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">)
svg << %(<rect width="#{width}" height="#{height}" fill="#F5F0E6"/>)
svg << %(<path d="M0 0H1200V18H0Z" fill="#173F3A"/>)
svg << %(<text x="60" y="76" font-family="Georgia,serif" font-size="36" font-weight="700" fill="#173F3A">Amber demo hosting economics</text>)
svg << %(<text x="60" y="114" font-family="Avenir Next,Helvetica,sans-serif" font-size="18" fill="#51625F">Shared CPU wins cost; dedicated CPU wins tail-latency predictability</text>)
svg << %(<text x="#{left_x}" y="#{top - 42}" font-family="Avenir Next,Helvetica,sans-serif" font-size="20" font-weight="700" fill="#173F3A">Apps per host</text>)
svg << %(<text x="#{right_x}" y="#{top - 42}" font-family="Avenir Next,Helvetica,sans-serif" font-size="20" font-weight="700" fill="#173F3A">Recommended monthly cost per app</text>)

labels.each_with_index do |label, index|
  plan = plans.fetch(label)
  y = top + index * (bar_height + bar_gap)
  color = colors.fetch(label)
  name = CGI.escapeHTML(display_name.fetch(label))
  measured_width = plan.fetch("healthy_apps") / max_capacity * panel_width
  recommended_width = plan.fetch("recommended_apps") / max_capacity * panel_width
  cost_width = plan.fetch("monthly_cost_per_recommended_app") / max_recommended_cost * panel_width

  svg << %(<text x="#{left_x}" y="#{y - 12}" font-family="Avenir Next,Helvetica,sans-serif" font-size="15" fill="#354744">#{name}</text>)
  svg << %(<rect x="#{left_x}" y="#{y}" width="#{panel_width}" height="#{bar_height}" rx="8" fill="#E3DDD1"/>)
  svg << %(<rect x="#{left_x}" y="#{y}" width="#{measured_width.round(1)}" height="#{bar_height}" rx="8" fill="#{color}" opacity="0.35"/>)
  svg << %(<rect x="#{left_x}" y="#{y}" width="#{recommended_width.round(1)}" height="#{bar_height}" rx="8" fill="#{color}"/>)
  capacity_text = recommended_width > 180 ? "#FFFFFF" : "#173F3A"
  svg << %(<text x="#{left_x + 14}" y="#{y + 39}" font-family="Avenir Next,Helvetica,sans-serif" font-size="21" font-weight="700" fill="#{capacity_text}">#{plan.fetch('recommended_apps')} safe / #{plan.fetch('healthy_apps')} edge</text>)

  svg << %(<text x="#{right_x}" y="#{y - 12}" font-family="Avenir Next,Helvetica,sans-serif" font-size="15" fill="#354744">#{name}</text>)
  svg << %(<rect x="#{right_x}" y="#{y}" width="#{panel_width}" height="#{bar_height}" rx="8" fill="#E3DDD1"/>)
  svg << %(<rect x="#{right_x}" y="#{y}" width="#{cost_width.round(1)}" height="#{bar_height}" rx="8" fill="#{color}"/>)
  svg << %(<text x="#{right_x + 14}" y="#{y + 39}" font-family="Avenir Next,Helvetica,sans-serif" font-size="21" font-weight="700" fill="#{cost_width > 100 ? '#FFFFFF' : '#173F3A'}">#{format('$%.3f', plan.fetch('monthly_cost_per_recommended_app'))}</text>)
end

svg << %(<line x1="60" y1="560" x2="1140" y2="560" stroke="#C9C0B1" stroke-width="1"/>)
svg << %(<rect x="72" y="594" width="34" height="14" rx="3" fill="#1D7874"/>)
svg << %(<text x="116" y="607" font-family="Avenir Next,Helvetica,sans-serif" font-size="15" fill="#51625F">Recommended operating cap</text>)
svg << %(<rect x="342" y="594" width="34" height="14" rx="3" fill="#1D7874" opacity="0.35"/>)
svg << %(<text x="386" y="607" font-family="Avenir Next,Helvetica,sans-serif" font-size="15" fill="#51625F">Additional measured edge</text>)
svg << %(<text x="60" y="655" font-family="Avenir Next,Helvetica,sans-serif" font-size="16" fill="#51625F">216 capacity trials, 6 smoke trials, 90 integrity checks, zero request errors, zero OOM kills.</text>)
svg << %(<text x="60" y="689" font-family="Avenir Next,Helvetica,sans-serif" font-size="16" fill="#51625F">Workload per app: 1,000 routes, 1M rows, SQLite FULL, 2 RPS steady, 10 RPS burst.</text>)
svg << %(<text x="60" y="730" font-family="Georgia,serif" font-size="16" font-style="italic" fill="#173F3A">Amber V2 performance research, Round 24</text>)
svg << %(</svg>)
File.write(options[:svg], svg.join("\n") + "\n")

puts "Wrote #{options[:markdown]} and #{options[:svg]}"
