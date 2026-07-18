#!/usr/bin/env ruby

require "cgi"
require "fileutils"
require "json"

ROOT_DIR = File.expand_path("../..", __dir__)
INPUT = File.expand_path(
  ARGV[0] || File.join(ROOT_DIR, "benchmarks", "results", "round23_digitalocean_database_matrix.json")
)
OUTPUT = File.expand_path(
  ARGV[1] || File.join(ROOT_DIR, "benchmarks", "results", "round23_database_overview.svg")
)

data = JSON.parse(File.read(INPUT))
scenario_labels = {
  "login" => "Login + bcrypt",
  "read_hot" => "Hot indexed reads",
  "read_broad" => "Million-row reads",
  "mixed_journey" => "Mixed app journey",
  "crud_cycle" => "CRUD write cycle",
}
series = [
  ["postgres", "PostgreSQL", "#173f3a"],
  ["sqlite_full", "SQLite FULL", "#c65f2f"],
  ["sqlite_normal", "SQLite NORMAL*", "#d59b2d"],
]

rows = scenario_labels.map do |scenario, label|
  values = data.fetch("aggregates").fetch(scenario).fetch("16")
  postgres_rps = values.dig("postgres", "requests_per_second", "median")
  {
    scenario: scenario,
    label: label,
    values: series.to_h do |key, name, color|
      rps = values.dig(key, "requests_per_second", "median")
      [key, {name: name, color: color, rps: rps, ratio: rps / postgres_rps}]
    end,
  }
end

def rate(value)
  value >= 100 ? format("%,.0f", value) : format("%.1f", value)
rescue ArgumentError
  value >= 100 ? format("%.0f", value) : format("%.1f", value)
end

width = 1_440
height = 1_030
plot_left = 310
plot_width = 850
plot_top = 190
row_height = 134
bar_height = 24
bar_gap = 8
ratio_max = 6.0

svg = []
svg << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}" role="img" aria-labelledby="title desc">)
svg << %(<title id="title">Amber V2 same-host PostgreSQL and SQLite throughput comparison</title>)
svg << %(<desc id="desc">Median requests per second normalized to PostgreSQL across login, indexed reads, broad million-row reads, a mixed application journey, and a CRUD write cycle.</desc>)
svg << <<~CSS
  <style>
    .title { font: 500 42px 'Avenir Next', 'Trebuchet MS', sans-serif; fill: #182824; }
    .subtitle { font: 400 21px 'Avenir Next', 'Trebuchet MS', sans-serif; fill: #596762; }
    .label { font: 500 20px 'Avenir Next', 'Trebuchet MS', sans-serif; fill: #182824; }
    .small { font: 400 16px 'Avenir Next', 'Trebuchet MS', sans-serif; fill: #596762; }
    .value { font: 500 16px 'Avenir Next', 'Trebuchet MS', sans-serif; fill: #182824; }
    .legend { font: 400 17px 'Avenir Next', 'Trebuchet MS', sans-serif; fill: #344641; }
    .callout-title { font: 500 18px 'Avenir Next', 'Trebuchet MS', sans-serif; fill: #182824; }
    .callout { font: 400 16px 'Avenir Next', 'Trebuchet MS', sans-serif; fill: #4f5f5a; }
  </style>
CSS
svg << %(<rect width="#{width}" height="#{height}" rx="28" fill="#f3eee2"/>)
svg << %(<path d="M0 0 H#{width} V112 C1100 154 820 78 510 126 C300 158 140 144 0 112 Z" fill="#e8dcc5" opacity="0.72"/>)
svg << %(<text x="64" y="64" class="title">One small host, two very different database tradeoffs</text>)
svg << %(<text x="64" y="101" class="subtitle">Amber V2, 1,000 routes, 1M resources, 16 clients, seven rotated repetitions</text>)

legend_x = 830
series.each_with_index do |(_key, name, color), index|
  x = legend_x + index * 180
  svg << %(<rect x="#{x}" y="132" width="18" height="18" rx="5" fill="#{color}"/>)
  svg << %(<text x="#{x + 28}" y="147" class="legend">#{CGI.escapeHTML(name)}</text>)
end

7.times do |tick|
  ratio = tick.to_f
  x = plot_left + (ratio / ratio_max) * plot_width
  svg << %(<line x1="#{x.round(1)}" y1="#{plot_top - 20}" x2="#{x.round(1)}" y2="#{plot_top + row_height * rows.size - 18}" stroke="#d8cfbd" stroke-width="1"/>)
  svg << %(<text x="#{x.round(1)}" y="#{plot_top - 30}" text-anchor="middle" class="small">#{tick}x</text>)
end
svg << %(<line x1="#{plot_left + plot_width / ratio_max}" y1="#{plot_top - 20}" x2="#{plot_left + plot_width / ratio_max}" y2="#{plot_top + row_height * rows.size - 18}" stroke="#173f3a" stroke-width="2" opacity="0.45"/>)

rows.each_with_index do |row, row_index|
  y = plot_top + row_index * row_height
  svg << %(<text x="64" y="#{y + 31}" class="label">#{CGI.escapeHTML(row.fetch(:label))}</text>)
  svg << %(<text x="64" y="#{y + 55}" class="small">median requests/sec</text>)
  series.each_with_index do |(key, _name, _color), series_index|
    value = row.fetch(:values).fetch(key)
    bar_y = y + series_index * (bar_height + bar_gap)
    bar_width = value.fetch(:ratio) / ratio_max * plot_width
    svg << %(<rect x="#{plot_left}" y="#{bar_y}" width="#{bar_width.round(1)}" height="#{bar_height}" rx="7" fill="#{value.fetch(:color)}"/>)
    text_x = [plot_left + bar_width + 12, plot_left + 72].max
    svg << %(<text x="#{text_x.round(1)}" y="#{bar_y + 18}" class="value">#{format('%.2fx', value.fetch(:ratio))}  #{rate(value.fetch(:rps))} RPS</text>)
  end
end

callout_y = 885
callouts = [
  ["READ-HEAVY", "SQLite FULL is 2.23x to 2.50x PostgreSQL", "Lower p99 and memory at FULL durability."],
  ["STRICT WRITES", "PostgreSQL is 1.79x SQLite FULL", "FULL is storage-latency bound on this disk."],
  ["LOGIN", "All engines stop near 12 to 13 logins/sec", "Bcrypt cost 10 sets this ceiling."],
]
callouts.each_with_index do |(title, headline, detail), index|
  x = 64 + index * 442
  svg << %(<rect x="#{x}" y="#{callout_y}" width="414" height="105" rx="18" fill="#fffaf0" stroke="#d8cfbd"/>)
  svg << %(<text x="#{x + 22}" y="#{callout_y + 27}" class="small">#{title}</text>)
  svg << %(<text x="#{x + 22}" y="#{callout_y + 55}" class="callout-title">#{CGI.escapeHTML(headline)}</text>)
  svg << %(<text x="#{x + 22}" y="#{callout_y + 82}" class="callout">#{CGI.escapeHTML(detail)}</text>)
end
svg << %(<text x="64" y="1015" class="small">* SQLite NORMAL is a deliberate weaker power-loss durability lane, not an apples-to-apples replacement for FULL.</text>)
svg << %(</svg>)

FileUtils.mkdir_p(File.dirname(OUTPUT))
File.write(OUTPUT, svg.join("\n"))
puts "Wrote #{OUTPUT}"
