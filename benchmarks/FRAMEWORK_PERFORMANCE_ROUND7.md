# Framework Performance Round 7

Round 7 tested a bigger validation-cache idea instead of another tiny cleanup:

- define validation rules once with `Amber::Validators::Params.define`
- reuse those compiled definitions per request with `validation(definition)`
- measure whether “build once, apply many times” actually beats the current
  per-request validation DSL

## Verdict

Do not promote this as a default framework change.

The idea is real, but this implementation only wins on the JSON-body side. It
regresses plain query validation enough that I would not merge it into the main
performance branch as-is.

## What Was Tested

The candidate branch adds:

- compiled validation definitions in `src/amber/validators/params.cr`
- schema-wrapper forwarding for `validation(definition)` in
  `src/amber/controller/schema_integration.cr`
- compiled-validation benchmark scenarios in:
  - `benchmarks/framework_performance_lab.cr`
  - `benchmarks/framework_performance_profile.cr`
- reuse and parity specs in `spec/amber/validations/params_spec.cr`

Validation and compatibility checks passed:

- `spec/amber/validations/params_spec.cr`
- `spec/amber/controller/schema_integration_spec.cr`
- `crystal eval` smoke checks for:
  - `Amber::Validators::Params.define`
  - controller use through `legacy_params.validation(definition)`

Important caveat:

- the full `framework_performance_lab` build still hit the local Crystal
  codegen/cache instability on this macOS machine
- the smaller release-built profile harness did build and run cleanly under
  both `crystal` and `acrystal`, so I used that focused harness for the round-7
  decision

## Focused Profile Read

Result files:

- `benchmarks/results/framework_profile_round7_validation_compare_crystal.txt`
- `benchmarks/results/framework_profile_round7_validation_compare_acrystal.txt`

### `crystal`

Query validation got worse:

- validated query params:
  - `1,722,353`
  - `1,616,775`
  - average `1,669,564`
- compiled query params:
  - `1,388,176`
  - `1,354,986`
  - average `1,371,581`
- compiled vs validated: `0.8215x` (`-17.9%`)

JSON-body validation got much better:

- validated JSON-body params:
  - `1,461,786`
  - `1,772,481`
  - average `1,617,133.5`
- compiled JSON-body params:
  - `1,960,912`
  - `2,090,493`
  - average `2,025,702.5`
- compiled vs validated: `1.2527x` (`+25.3%`)

### `acrystal`

The same direction showed up here too, just less dramatically on query params:

- validated query params average: `1,156,774.5`
- compiled query params average: `1,090,772`
- compiled vs validated: `0.9429x` (`-5.7%`)

- validated JSON-body params average: `1,094,871`
- compiled JSON-body params average: `1,237,371.5`
- compiled vs validated: `1.1302x` (`+13.0%`)

That consistency is useful. It makes this look less like random noise and more
like a real split in the implementation.

## Practical Read

The plain-English version:

- caching validation definitions helps on heavier JSON-body validation
- the generic compiled-rule interpreter is not cheap enough to beat the current
  query-param validation path

So the main lesson is not “caching is bad.” It is:

- generic cached definitions are too blunt
- specialized compiled validators may still be a strong idea

## Best Next Move

If we keep pushing in this area, I would try one of these next:

- a macro-generated validator that emits direct checks for a specific rule set
- a specialized fast path for simple required-field groups without the generic
  `RuleKind` switch and predicate indirection
- a JSON-body-only opt-in path if we want to keep exploring this idea without
  slowing query validation
