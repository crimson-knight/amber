# Framework Performance Hypotheses

This file is the starting board for Amber's framework-wide performance lab.

## How To Read The Ratios

The framework lab compares Amber behavior against a simpler baseline.

- `1.00x` means the candidate matches the baseline.
- `< 1.00x` means the candidate is slower.
- `> 1.00x` means the candidate is faster.

Examples:

- `0.50x` means Amber is running at 50% of the baseline throughput.
  That is roughly `2x` slower.
- `0.25x` means Amber is running at 25% of the baseline throughput.
  That is roughly `4x` slower.
- `0.90x` means Amber is about 10% slower.

The easiest human read is usually `slower_factor`.

## Current Baseline Read

The first framework lab baselines point to request parsing and parameter access
as the biggest framework-wide cost center.

Shared direction across both compilers:

- controller param access is roughly `4.3x` to `4.5x` slower than the Amber
  params lookup directly
- Amber JSON-body params lookup is roughly `3.2x` slower than raw JSON parse
- Amber full JSON-body dispatch is roughly `3.1x` slower than the Amber params
  lookup itself
- Amber query lookup is roughly `2x` slower than raw query parsing
- plaintext and JSON dispatch overhead exist, but they are secondary compared
  with request parsing

## Parent Benchmark Base

- Branch: `experiment/framework-performance-base`
- Source commit: benchmark lab base cut from the current router-performance lab
- Canonical baselines:
  - `benchmarks/results/framework_performance_lab_baseline_crystal.json`
  - `benchmarks/results/framework_performance_lab_baseline_acrystal.json`

## Parallel Hypotheses

### Hypothesis 1: Params Fast Paths

If Amber avoids paying for every param source on every lookup, query-heavy and
JSON-body-heavy requests should move much closer to raw parsing.

Target files:

- `src/amber/router/params.cr`
- `src/amber/router/parsers/json.cr`

Focus:

- short-circuit source selection by content type and method
- avoid unnecessary merges and wrapper creation
- cache direct query and JSON lookups more cheaply

### Hypothesis 2: Controller Param Wrapper Overhead

If controller setup stops eagerly building compatibility wrappers and validator
objects, controller-level param scenarios should close a large portion of the
gap without affecting routing.

Target files:

- `src/amber/controller/base.cr`
- `src/amber/controller/schema_integration.cr`

Focus:

- lazy-init `original_params`
- reduce always-on compatibility allocation
- preserve behavior while removing hot-path setup cost

### Hypothesis 3: JSON Dispatch And Negotiation

If Amber trims responder and response-finalization work for common JSON cases,
the `json` dispatch gap should shrink even when parsing stays the same.

Target files:

- `src/amber/controller/helpers/responders.cr`
- `src/amber/router/context.cr`

Focus:

- simplify Accept handling for common cases
- reduce response finalization overhead
- keep behavior stable for `respond_with`

## Iteration Rule

Each branch should change one theory only, then re-run:

1. `framework_performance_lab`
2. matching external HTTP benchmark
3. parity or targeted correctness checks

If the branch wins the lab but loses external throughput or correctness, it does
not advance.
