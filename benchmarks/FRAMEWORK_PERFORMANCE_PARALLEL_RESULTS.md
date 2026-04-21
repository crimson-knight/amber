# Framework Performance Parallel Results

This note records the first parallel experiment round from the benchmark base
branch `experiment/framework-performance-base`.

## How To Read This

- `1.00x` means no change versus the baseline.
- `1.25x` means about `25%` faster.
- `0.80x` means about `20%` slower.

When comparing Amber to a simpler baseline inside the framework lab:

- a higher `ips_ratio` is better
- a lower `slower_factor` is better

## Round 1 Verdict

Promote now:

- params fast paths
- controller param laziness

Keep isolated for now:

- JSON dispatch and negotiation fast paths

## Why These Two Advance

The params fast-path work is the clearest cross-compiler win.

From the baseline to the promoted winner set:

- `amber_params_lookup_query`
  - `crystal`: `831k -> 1.087M` IPS (`+30.7%`)
  - `acrystal`: `884k -> 1.103M` IPS (`+24.8%`)
- `amber_params_lookup_json`
  - `crystal`: `485k -> 879k` IPS (`+81.2%`)
  - `acrystal`: `508k -> 885k` IPS (`+74.3%`)
- `amber_dispatch_json_body`
  - `crystal`: `157k -> 188k` IPS (`+19.3%`)
  - `acrystal`: `161k -> 169k` IPS (`+5.3%`)

Inside the same run, Amber also moved materially closer to raw parsing:

- query lookup vs raw parse ratio:
  - `crystal`: `0.495x -> 0.663x`
  - `acrystal`: `0.498x -> 0.680x`
- JSON body params vs raw JSON parse ratio:
  - `crystal`: `0.308x -> 0.647x`
  - `acrystal`: `0.310x -> 0.621x`

The controller wrapper work is a narrower win, but it is still worth keeping.
It removes eager compatibility allocation from controller setup and caches the
schema wrapper only when it is needed. In the targeted schema-path run from the
parallel worktree, that moved throughput from `18.99M -> 22.49M` IPS (`+18.4%`)
while dropping allocations from `48 -> 16 B/op` (`-66.7%`).

## Why JSON Dispatch Stays Experimental

The JSON dispatch and negotiation branch looked promising in isolation, but the
stacked runs were mixed once combined with the params and controller changes.
That means it is not mature enough to promote into the main experiment branch
yet.

The right next step is to retest that branch with a longer external HTTP run and
only advance it if the gain survives outside the micro-lab.
