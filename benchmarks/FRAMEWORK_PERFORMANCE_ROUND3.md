# Framework Performance Round 3

Round 3 used parallel experiment branches off `4e6922d` to test three
high-confidence ideas:

- response output/finalization fast path
- dispatch bookkeeping cleanup
- request method caching

## Verdict

Promote two changes:

- dispatch bookkeeping cleanup
- request method caching, but only for repeated `POST` method resolution

Reject one change:

- response output/content-length fast path

The response branch produced mixed results and did not hold up as a reliable
win in same-session A/B testing, so it should not be stacked into the winner
set.

## Promoted Code Paths

- `src/amber/pipes/pipeline.cr`
  - cache `request`
  - keep websocket short-circuit ahead of route bookkeeping
  - reuse the resolved route for constraint and valve lookup
- `src/amber/router/context.cr`
  - cache `response.headers` locally inside `finalize_response!`
- `src/amber/router/request.cr`
  - cache resolved `POST` override method only
  - do not add extra memoization overhead to non-`POST` requests

## Crystal Result

Using `benchmarks/results/framework_performance_lab_round3_crystal.json`,
Round 3 improved the current promoted Round 2 state in the areas we care about:

- `amber_dispatch_plaintext`: `280,859 -> 297,485` IPS (`+5.9%`)
- `amber_dispatch_json`: `259,263 -> 264,478` IPS (`+2.0%`)
- `amber_dispatch_json_body`: `189,481 -> 314,849` IPS (`+66.2%`)
- `amber_dispatch_route_query_params`: `196,012 -> 208,480` IPS (`+6.4%`)
- `amber_dispatch_plaintext_3pipes`: `273,032 -> 305,225` IPS (`+11.8%`)
- `amber_action_json_direct`: `295,758 -> 336,853` IPS (`+13.9%`)
- `amber_action_json_respond_with`: `285,574 -> 298,899` IPS (`+4.7%`)

Relative to the original framework baseline, the six main framework-lab
hotspots are now about `1.521x` mean and `1.477x` geometric mean faster on
stock `crystal`.

## ACrystal Result

`acrystal` stayed source-compatible and compiled cleanly for every promoted
change.

The short rerun in
`benchmarks/results/framework_performance_lab_round3_acrystal_rerun.json`
showed the promoted set still improving the practical JSON-heavy and dispatch
paths versus the original baseline:

- `amber_dispatch_json`: `197,611 -> 233,908` IPS (`+18.4%`)
- `amber_dispatch_json_body`: `160,543 -> 274,719` IPS (`+71.1%`)
- `amber_params_lookup_json`: `507,594 -> 989,192` IPS (`+94.9%`)

However, longer same-session `acrystal` A/B runs against a fresh Round 2
control stayed noisy on this local machine, especially on GET-heavy controller
paths. The long control and stacked files are:

- `benchmarks/results/framework_performance_lab_round2_control_acrystal_long.json`
- `benchmarks/results/framework_performance_lab_round3_acrystal_v2_long.json`

So the honest read is:

- compatibility is good
- the JSON-heavy `acrystal` paths still look better than baseline
- the exact stacked delta versus Round 2 is still inconclusive locally and
  should be rerun on quieter hosted hardware

## Profile Read

The current sample trace is still dominated by response output and GC work in
`HTTP::Server::Response::Output`, which means request/response allocation
pressure is still the next frontier after this round.

See:

- `benchmarks/results/framework_profile_round3_dispatch_json_body.sample.txt`

## Visual

Updated stacked comparison:

- `benchmarks/results/framework_performance_progress_round3.svg`
