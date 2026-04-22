# Framework Performance Round 9

Round 9 took the next step after the direct compiled validator prototype:

- keep the direct generated validator fast path from Round 8
- preserve full validation capability by falling back per rule instead of
  rejecting the whole compiled validator
- unify reusable validator handling so generic reusable definitions and direct
  compiled validators flow through the same request-time interface

## Verdict

Keep the direction, with one important caveat.

This round successfully preserves mixed-rule capability inside
`Params.compile`, keeps the simple direct compiled path fast, and makes the
reusable validator story cleaner. It does **not** yet prove that every
mixed-rule hybrid validator is faster than the runtime DSL on both compilers.

## What Changed

Files:

- `src/amber/validators/params.cr`
- `src/amber/controller/schema_integration.cr`
- `spec/amber/validations/params_spec.cr`
- `spec/amber/controller/schema_integration_spec.cr`
- `benchmarks/framework_performance_lab.cr`
- `benchmarks/framework_performance_profile.cr`

Main implementation points:

- introduced a shared `ReusableDefinition` contract
- made `Definition` implement reusable `apply`
- unified `Params#validation` / `Params#valid?` around one reusable-definition
  path
- changed `Params.compile NAME do ... end` to lower rules one by one:
  - direct inline emission for simple supported rules
  - reusable fallback definitions for unsupported rules such as predicate
    blocks
- expanded specs for mixed-rule parity and schema-wrapper parity
- expanded the perf harnesses with mixed and hybrid validation scenarios

## Validation Status

Passed:

- `CRYSTAL_WORKERS=1 crystal spec spec/amber/validations/params_spec.cr spec/amber/controller/schema_integration_spec.cr`
  - `39 examples, 0 failures`
- `CRYSTAL_WORKERS=1 crystal build --error-trace --no-codegen benchmarks/framework_performance_profile.cr`
- `CRYSTAL_WORKERS=1 acrystal build --error-trace --no-codegen benchmarks/framework_performance_profile.cr`
- `CRYSTAL_WORKERS=1 crystal build --error-trace --no-codegen benchmarks/framework_performance_lab.cr`

Notes:

- the only build output was the existing deprecated `File.readable?` warning in
  Amber support code

## Focused Profile Read

The canonical result files for this round are the alternating-order reruns:

- `benchmarks/results/framework_profile_round9_validation_compare_crystal_rerun.txt`
- `benchmarks/results/framework_profile_round9_validation_compare_acrystal_rerun.txt`
- `benchmarks/results/framework_performance_lab_round9_crystal.json`

### `crystal`

- simple query compiled vs runtime validated: `1.1684x` (`+16.8%`)
- mixed query hybrid vs runtime validated: `1.1608x` (`+16.1%`)
- simple JSON-body compiled vs runtime validated: `1.2503x` (`+25.0%`)
- mixed JSON-body hybrid vs runtime validated: `1.0483x` (`+4.8%`)

### `acrystal`

- simple query compiled vs runtime validated: `1.3127x` (`+31.3%`)
- mixed query hybrid vs runtime validated: `0.9535x` (`-4.7%`)
- simple JSON-body compiled vs runtime validated: `1.0625x` (`+6.3%`)
- mixed JSON-body hybrid vs runtime validated: `1.1998x` (`+20.0%`)

## Full-Lab Smoke Read

A short stock-`crystal` framework-lab run was also left on the branch as a
regression screen. It is not the primary promotion gate, but it broadly agrees
with the focused harness:

- `query_action_compiled_vs_validated`: `1.0388x`
- `query_action_hybrid_vs_mixed`: `1.0866x`
- `json_body_action_compiled_vs_validated`: `1.1832x`
- `json_body_action_hybrid_vs_mixed`: `1.0696x`

## Practical Read

The plain-English version:

- Round 8 proved that direct generated validators can be faster
- Round 9 proves that we can preserve predicate-block and mixed-rule capability
  inside the compiled API instead of failing fast
- the simple direct compiled path still looks clearly worth keeping
- the mixed fallback path is promising, but it is not yet uniformly better on
  every compiler and workload shape

That means this branch is a good checkpoint and a good implementation
foundation, but not yet a blanket “everything compiled is always faster”
promotion.

## Best Next Move

The next worthwhile step is to tighten the mixed fallback path before
promoting this into the main performance branch:

- add compile diagnostics so we can see direct-rule count vs fallback-rule count
- investigate why `acrystal` query hybrid underperformed on the mixed case
- only after that, add the higher-level controller declaration API for hot-path
  validations
