# Framework Performance Round 2

Round 2 focuses on a single next-pass change:

- make `Amber::Validators::Params` lazy on the read-only path

That means common controller code that only reads `params["..."]` no longer pays
to eagerly allocate validation arrays and hashes before any validation API is
actually used.

## Verdict

Keep this change.

It validated cleanly and it improved the real request-path scenarios that matter
more than the micro-ratio alone.

Validation performed:

- `spec/amber/validations/params_spec.cr`
- `spec/amber/controller/schema_integration_spec.cr`
- `crystal build --no-codegen benchmarks/framework_performance_lab.cr`
- `crystal build --no-codegen benchmarks/framework_performance_profile.cr`

## Absolute Throughput Wins

Compared with the promoted winner set from Round 1:

### Crystal

- `amber_action_query_params`: `188,857 -> 217,305` IPS (`+15.1%`)
- `amber_params_lookup_query`: `1,086,718 -> 1,163,949` IPS (`+7.1%`)
- `amber_params_lookup_json`: `878,509 -> 1,002,491` IPS (`+14.1%`)
- `amber_dispatch_plaintext`: `250,285 -> 280,859` IPS (`+12.2%`)
- `amber_dispatch_json`: `213,648 -> 259,263` IPS (`+21.4%`)
- `amber_dispatch_json_body`: `187,522 -> 189,481` IPS (`+1.0%`)

### ACrystal

- `amber_action_query_params`: `202,055 -> 231,442` IPS (`+14.5%`)
- `amber_params_lookup_query`: `1,102,532 -> 1,190,928` IPS (`+8.0%`)
- `amber_params_lookup_json`: `884,731 -> 1,018,347` IPS (`+15.1%`)
- `amber_dispatch_plaintext`: `267,502 -> 298,469` IPS (`+11.6%`)
- `amber_dispatch_json`: `196,183 -> 277,922` IPS (`+41.7%`)
- `amber_dispatch_json_body`: `169,007 -> 311,244` IPS (`+84.2%`)

## Why Some Ratios Look Worse While The App Path Looks Better

Two comparisons are easy to misread:

- `query_action_vs_params`
- `json_dispatch_vs_params`

Those ratios compare a slower, more complete controller/dispatch path against a
faster micro-path. If the micro-path speeds up even faster than the full path,
the ratio can go down even when the full path itself got faster.

That happened here on `crystal`:

- `amber_dispatch_json_body` improved in absolute terms (`+1.0%`)
- but `amber_params_lookup_json` improved even more (`+14.1%`)
- so `json_dispatch_vs_params` went from `0.213x -> 0.189x`

The ratio is still useful, but it is not the only decision signal. The
framework-level decision should follow the absolute request path plus the
correctness checks, and this round passes both.

## Profile Harness Read

The dedicated profile harness also improved:

- `action_query_params`
  - before: `2,996,869` iterations in `15s`
  - after: `4,447,365` iterations in `15s`
  - delta: about `+48.4%`
- `dispatch_json_body`
  - before: `2,687,749` iterations in `15s`
  - after: `3,247,023` iterations in `15s`
  - delta: about `+20.8%`

The `sample` traces still show allocation and GC pressure dominating the top of
the stack, especially around response output and request object creation, which
means there is still room left after this round.

## Actionable Next Target

The next best place to keep pushing is request/response allocation pressure, not
route matching.

Most likely next themes:

- reduce response write allocations in the controller/dispatch path
- reduce per-request context/request construction churn in the benchmarked path
- keep validation compatibility lazy unless validation APIs are actually used

## Visual

See `benchmarks/results/framework_performance_progress.svg` for the normalized
baseline vs Round 1 vs Round 2 comparison.
