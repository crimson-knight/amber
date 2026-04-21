#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

if ARGV.size != 7
  warn "Usage: framework_perf_progress_svg.rb base_crystal winner_crystal round2_crystal base_acrystal winner_acrystal round2_acrystal output.svg"
  exit 1
end

SCENARIOS = [
  ["amber_action_query_params", "Controller query params"],
  ["amber_params_lookup_query", "Params lookup query"],
  ["amber_params_lookup_json", "Params lookup JSON body"],
  ["amber_dispatch_json_body", "Dispatch JSON body"],
  ["amber_dispatch_plaintext", "Dispatch plaintext"],
  ["amber_dispatch_json", "Dispatch JSON"],
].freeze

STAGES = [
  ["Baseline", "#B0B7C3"],
  ["Winner Set", "#D39B2A"],
  ["Round 2", "#2E9D65"],
].freeze

def load_results(path)
  payload = JSON.parse(File.read(path))
  payload.fetch("results").each_with_object({}) do |row, acc|
    acc[row.fetch("key")] = row.fetch("ips")
  end
end

base_crystal, winner_crystal, round2_crystal, base_acrystal, winner_acrystal, round2_acrystal, output_path = ARGV

datasets = {
  "Crystal" => [
    load_results(base_crystal),
    load_results(winner_crystal),
    load_results(round2_crystal),
  ],
  "ACrystal" => [
    load_results(base_acrystal),
    load_results(winner_acrystal),
    load_results(round2_acrystal),
  ],
}

max_ratio = datasets.values.flat_map do |stages|
  baseline = stages.first
  stages.flat_map do |rows|
    SCENARIOS.map { |key, _| rows.fetch(key) / baseline.fetch(key) }
  end
end.max

max_ratio = [max_ratio, 1.1].max

panel_width = 640
panel_height = 470
margin = 40
label_x = 20
bar_x = 250
bar_width = 320
scenario_y_gap = 64
stage_gap = 16
bar_height = 12

svg_width = panel_width * 2 + margin * 2
svg_height = panel_height + margin * 2

def fmt_ips(value)
  if value >= 1_000_000
    format("%.2fM", value / 1_000_000.0)
  else
    format("%.0fk", value / 1_000.0)
  end
end

def fmt_ratio(value)
  format("%.2fx", value)
end

svg = +""
svg << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{svg_width}" height="#{svg_height}" viewBox="0 0 #{svg_width} #{svg_height}">)
svg << %(<style>
  text { font-family: Menlo, Monaco, Consolas, "Liberation Mono", monospace; fill: #1F2937; }
  .title { font-size: 24px; font-weight: 700; }
  .subtitle { font-size: 13px; fill: #4B5563; }
  .panel-title { font-size: 18px; font-weight: 700; }
  .label { font-size: 12px; }
  .value { font-size: 11px; }
  .legend { font-size: 12px; }
</style>)
svg << %(<rect width="100%" height="100%" fill="#FAFAF8"/>)
svg << %(<text x="#{margin}" y="32" class="title">Amber Framework Performance Progress</text>)
svg << %(<text x="#{margin}" y="54" class="subtitle">Normalized to the original framework-lab baseline for each compiler. Longer bars are better.</text>)

STAGES.each_with_index do |(label, color), index|
  legend_x = margin + index * 150
  svg << %(<rect x="#{legend_x}" y="72" width="14" height="14" rx="3" fill="#{color}"/>)
  svg << %(<text x="#{legend_x + 22}" y="84" class="legend">#{label}</text>)
end

datasets.each_with_index do |(compiler, stages), panel_index|
  origin_x = margin + panel_index * panel_width
  origin_y = 110

  svg << %(<rect x="#{origin_x}" y="#{origin_y}" width="#{panel_width - 20}" height="#{panel_height}" rx="16" fill="#FFFFFF" stroke="#E5E7EB"/>)
  svg << %(<text x="#{origin_x + 20}" y="#{origin_y + 28}" class="panel-title">#{compiler}</text>)

  baseline = stages.first

  SCENARIOS.each_with_index do |(key, label), row_index|
    y = origin_y + 70 + row_index * scenario_y_gap
    svg << %(<text x="#{origin_x + label_x}" y="#{y + 10}" class="label">#{label}</text>)

    STAGES.each_with_index do |(stage_label, color), stage_index|
      ips = stages.fetch(stage_index).fetch(key)
      ratio = ips / baseline.fetch(key)
      width = (ratio / max_ratio) * bar_width
      bar_y = y + 18 + stage_index * stage_gap
      svg << %(<rect x="#{origin_x + bar_x}" y="#{bar_y}" width="#{width}" height="#{bar_height}" rx="6" fill="#{color}"/>)
      svg << %(<text x="#{origin_x + bar_x + width + 8}" y="#{bar_y + 10}" class="value">#{stage_label}: #{fmt_ratio(ratio)} | #{fmt_ips(ips)}</text>)
    end
  end
end

svg << "</svg>\n"

File.write(output_path, svg)
