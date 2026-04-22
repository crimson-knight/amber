# Framework Performance Round 5

Round 5 did two things:

- tested a narrower write-path/content-length fast path
- expanded the framework lab so we can measure raw-vs-validated param access
  and keep a durable change history going forward

## Verdict

Reject the runtime write-path change.

Keep the benchmark and record-keeping additions:

- `benchmarks/framework_performance_lab.cr`
- `benchmarks/framework_performance_profile.cr`
- `benchmarks/README_FRAMEWORK_PERFORMANCE_LAB.md`
- `benchmarks/PERFORMANCE_CHANGE_LOG.md`

## Why The Runtime Change Does Not Advance

The key improvement in this round was meant to be:

- pre-size known string responses so Amber can avoid chunked write overhead

That idea looked promising in one early run, but I re-ran it against a
same-harness Round 4 control worktree so the comparison was not polluted by the
new benchmark scenarios themselves. Under that cleaner A/B, the response-path
change produced mixed results and important regressions.

Same-harness control:

- `benchmarks/results/framework_performance_lab_round5_same_harness_control_crystal.json`

Candidate branch:

- `benchmarks/results/framework_performance_lab_round5_crystal.json`

Key same-harness deltas on `crystal`:

- improved:
  - `amber_action_json_direct`: `251,584 -> 269,178` IPS (`+7.0%`)
  - `amber_action_json_respond_with`: `214,397 -> 240,460` IPS (`+12.2%`)
  - `amber_dispatch_json`: `182,021 -> 202,323` IPS (`+11.2%`)
  - `amber_params_lookup_query`: `1.148M -> 1.171M` IPS (`+2.0%`)
  - `amber_params_lookup_json`: `901,639 -> 936,205` IPS (`+3.8%`)
- regressed:
  - `amber_dispatch_plaintext`: `273,698 -> 246,500` IPS (`-9.9%`)
  - `amber_action_json_body_raw_params`: `275,404 -> 194,352` IPS (`-29.4%`)
  - `amber_action_json_body_validated_params`: `259,272 -> 172,256` IPS (`-33.6%`)
  - `amber_dispatch_json_body`: `264,242 -> 173,487` IPS (`-34.3%`)

That is not stable enough to stack into the main winner branch.

## What Round 5 Still Taught Us

The new raw-vs-validated scenarios are useful, and they answer a question that
kept coming up: how much does the flexibility layer cost if somebody wants the
absolute fastest endpoint?

Using the same-harness Round 4 control run:

- controller wrapped query params vs raw params:
  - ratio `0.984x`
  - only about `1.6%` slower
- controller validated query params vs raw params:
  - ratio `0.872x`
  - about `12.8%` slower
- controller validated JSON body params vs raw params:
  - ratio `0.941x`
  - about `5.9%` slower

That means the main cost is not the existing query/body wrapper by itself.
Amber's current wrapper overhead is already fairly small. The bigger cost is
the actual validation step, not the compatibility layer around it.

## Practical Read

Two conclusions look strong enough to carry forward:

1. Amber probably does not need a new public "raw params" escape hatch just to
   avoid wrapper overhead. The existing wrapper path is already close to raw in
   the query case.
2. If we want faster ultra-hot validated endpoints, the better target is the
   validation path itself, not a wholesale bypass of the wrapper.

## Next Target

Keep pushing on response/request overhead, but do it with narrower hypotheses
than the rejected content-length pass. The next worthwhile shape is likely:

- targeted responder/write-path profiling with the expanded profile harness
- smaller response-finalization hypotheses that do not perturb the JSON-body
  path so heavily
