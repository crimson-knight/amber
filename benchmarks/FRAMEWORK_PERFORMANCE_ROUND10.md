# Framework Performance Round 10

Round 10 went after the exact weak spot we left in Round 9:

- keep the Round 9 hybrid validator shape
- shrink the generic fallback tax inside `Params.compile`
- add metadata so we can see how much of a validator is direct vs fallback
- isolate the common predicate-block case instead of treating every block rule as
  fully generic

## Verdict

Do **not** promote this as the new default path yet.

This round is useful, and parts of it clearly moved in the right direction, but
the performance story is still split:

- the short full framework lab came back positive on both compilers
- the focused validation profile was still mixed, with real regressions in a few
  simple compiled cases

That means this is a good research checkpoint, but not a clean “ship it”
checkpoint.

## What Changed

Files:

- `src/amber/validators/params.cr`
- `spec/amber/validations/params_spec.cr`
- `benchmarks/framework_performance_profile.cr`
- `benchmarks/framework_performance_lab.cr`

Main implementation points:

- added reusable validator metadata:
  - `total_rule_count`
  - `direct_rule_count`
  - `fallback_rule_count`
  - `hybrid?`
- taught `Params.compile` to specialize the common statically knowable
  one-argument predicate-block rule instead of always routing it through the
  generic reusable fallback definition
- added explicit metadata export in the framework lab JSON so the benchmark
  output records the shape of each compiled validator
- added a predicate-only validation scenario to the focused profile harness so
  we can isolate the fallback-heavy query case directly
- expanded specs to cover:
  - direct predicate specialization parity
  - multiple opaque fallback rules
  - definition metadata counts

## Validation Status

Passed:

- `CRYSTAL_WORKERS=1 crystal spec spec/amber/validations/params_spec.cr spec/amber/controller/schema_integration_spec.cr`
  - `44 examples, 0 failures`
- `CRYSTAL_WORKERS=1 crystal build --error-trace --no-codegen benchmarks/framework_performance_profile.cr`
- `CRYSTAL_WORKERS=1 acrystal build --error-trace --no-codegen benchmarks/framework_performance_profile.cr`
- `CRYSTAL_WORKERS=1 crystal build --error-trace --no-codegen benchmarks/framework_performance_lab.cr`
- `CRYSTAL_WORKERS=1 acrystal build --error-trace --no-codegen benchmarks/framework_performance_lab.cr`

Notes:

- the only build output was the existing deprecated `File.readable?` warning in
  Amber support code

## Full-Lab Read

Canonical files:

- `benchmarks/results/framework_performance_lab_round10_crystal.json`
- `benchmarks/results/framework_performance_lab_round10_acrystal.json`

These short framework-lab runs were broadly positive on both compilers:

### `crystal`

- query compiled vs runtime validated: `1.0616x` (`+6.2%`)
- query hybrid vs mixed runtime validated: `1.0681x` (`+6.8%`)
- JSON-body compiled vs runtime validated: `1.0962x` (`+9.6%`)
- JSON-body hybrid vs mixed runtime validated: `1.0926x` (`+9.3%`)

### `acrystal`

- query compiled vs runtime validated: `1.0744x` (`+7.4%`)
- query hybrid vs mixed runtime validated: `1.1034x` (`+10.3%`)
- JSON-body compiled vs runtime validated: `1.1172x` (`+11.7%`)
- JSON-body hybrid vs mixed runtime validated: `1.0921x` (`+9.2%`)

The metadata in those JSON files also shows that the lowering logic is doing
what we intended:

- simple compiled validators: `3 direct / 0 fallback`
- hybrid compiled validators: `2 direct / 1 fallback`
- predicate-only compiled validator: `0 direct / 1 fallback`

## Focused Profile Read

Canonical files:

- `benchmarks/results/framework_profile_round10_validation_compare_crystal.txt`
- `benchmarks/results/framework_profile_round10_validation_compare_acrystal.txt`

These targeted validation-only runs were much less clean.

### `crystal`

- simple query compiled vs runtime validated: `0.9260x` (`-7.4%`)
- mixed query hybrid vs runtime validated: `0.9279x` (`-7.2%`)
- predicate-only query compiled vs runtime validated: `0.8706x` (`-12.9%`)
- simple JSON-body compiled vs runtime validated: `1.0132x` (`+1.3%`)
- mixed JSON-body hybrid vs runtime validated: `1.1294x` (`+12.9%`)

### `acrystal`

- simple query compiled vs runtime validated: `0.8553x` (`-14.5%`)
- mixed query hybrid vs runtime validated: `1.0764x` (`+7.6%`)
- predicate-only query compiled vs runtime validated: `0.9668x` (`-3.3%`)
- simple JSON-body compiled vs runtime validated: `0.9029x` (`-9.7%`)
- mixed JSON-body hybrid vs runtime validated: `0.9001x` (`-10.0%`)

## Practical Read

The plain-English version:

- the diagnostics are good and worth keeping around for future investigation
- the exact `acrystal` mixed-query fallback case we were targeting did improve
  in the focused profile compared with Round 9
- but the broader focused profile is still too unstable and contradictory to
  call this a default-on performance win

That contradiction matters. If the full lab says “better” while the focused
profile says “worse” for several simple paths, the responsible call is to stop
and not quietly merge it just because some of the numbers look nice.

## Best Next Move

The next useful move is not to keep piling more runtime cleverness onto this
branch. It is to settle the measurement disagreement first.

- rerun the focused validation profile on quieter hosted hardware
- if the contradiction remains, back out the predicate specialization and try a
  different fallback seam
- keep the metadata and predicate-only scenario as diagnostics, because they
  made this round much easier to reason about
