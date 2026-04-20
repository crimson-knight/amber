# Router Experiment Loop

This branch carries a side-by-side routing experiment so we can iterate on
matching strategies without losing the current implementation as a benchmark
baseline.

## Current setup

- `src/amber/router/engine/route_set.cr`
  Adds `#find_experimental_best`, an alternate matcher that keeps only the
  current winning route instead of collecting all matches and sorting later.
- `benchmarks/router_strategy_compare.cr`
  Runs the current matcher and experimental matcher against the same route
  sets and lookup paths, then writes JSON results to `benchmarks/results/`.
- `spec/amber/router/engine/route_set/matching/experimental_best_match_spec.cr`
  Checks semantic parity between the current and experimental matchers for the
  core route shapes we care about while iterating.

## How to run

Quick smoke benchmark:

```bash
bash benchmarks/bin/router_strategy_compare.sh --compiler crystal --tiers=100,1000 --warmup=1 --calc=1
```

Longer comparison:

```bash
bash benchmarks/bin/router_strategy_compare.sh --compiler acrystal --tiers=100,1000,5000,10000 --warmup=2 --calc=5
```

Targeted parity spec:

```bash
crystal spec spec/amber/router/engine/route_set/matching/experimental_best_match_spec.cr
```

Toolchain doctor:

```bash
bash benchmarks/bin/crystal_runtime_doctor.sh --compiler crystal
bash benchmarks/bin/crystal_runtime_doctor.sh --compiler acrystal
```

## Compatibility notes

- The benchmark wrapper normalizes the macOS toolchain so both Homebrew
  `crystal` and `acrystal` use the same Xcode SDK and `pkg-config` path without
  accidentally picking up a mismatched Homebrew `lld`.
- The doctor script builds and runs a tiny Crystal program before the real
  benchmark. If that smoke test times out, the problem is the local machine's
  executable launch policy rather than the Amber benchmark harness.
- The benchmark JSON now records `metadata.compiler` so cross-compiler result
  files are easy to compare later.

## Suggested iteration order

1. Benchmark the current experimental matcher.
2. If it wins and parity stays green, keep iterating inside that path.
3. If it loses, revert or replace the experiment method and keep the harness.
4. Only port changes into the default `#find` path after repeated wins.
