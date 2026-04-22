# Framework Performance Round 8

Round 8 took the next step after the rejected Round 7 cache experiment:

- stop rebuilding validation rules in the request path
- stop interpreting a generic cached rule array at runtime
- generate a direct validator ahead of time for simple required/optional field
  groups

This is much closer to the real idea behind the feedback: if the validation is
known when the app is compiled, the hot path should not still be paying to
assemble or interpret the same rule objects on every request.

## Verdict

Keep the direction. The direct generated validator path is the first validation
experiment in this area that produced a clean win on both compilers.

## What Was Tested

Two versions were measured in this round.

### Phase 1: Proc-Based Compiled Definitions

This kept the Round 7 idea but changed the validator definitions to be emitted
by a macro instead of built through the runtime DSL builder. The generated
definitions still ran through one proc call per request.

Files:

- `benchmarks/results/framework_profile_round8_validation_compare_crystal.txt`
- `benchmarks/results/framework_profile_round8_validation_compare_acrystal.txt`

Result:

- it was better than the old generic cached interpreter
- it still was not strong enough on stock `crystal` query validation

Measured read:

- `crystal` query compiled vs validated: `0.8742x`
- `crystal` JSON-body compiled vs validated: `1.1099x`
- `acrystal` query compiled vs validated: `1.0173x`
- `acrystal` JSON-body compiled vs validated: `1.1776x`

That was progress, but not enough.

### Phase 2: Direct Generated Validator Type

The kept version changes `Params.compile` into a top-level macro statement:

```crystal
Amber::Validators::Params.compile QUERY_VALIDATION do
  required(:page)
  required(:sort)
  required(:filter)
end
```

That macro now emits:

- a generated validator type
- a constant instance of that validator
- a direct `apply` method with field checks inlined

So the request path no longer walks a generic rule array and no longer pays the
extra proc hop from the first Phase 1 attempt.

Files:

- `src/amber/validators/params.cr`
- `src/amber/controller/schema_integration.cr`
- `spec/amber/validations/params_spec.cr`
- `benchmarks/framework_performance_lab.cr`
- `benchmarks/framework_performance_profile.cr`
- `benchmarks/results/framework_profile_round8_direct_validation_compare_crystal.txt`
- `benchmarks/results/framework_profile_round8_direct_validation_compare_acrystal.txt`

Validation checks passed:

- `spec/amber/validations/params_spec.cr`
- `spec/amber/controller/schema_integration_spec.cr`
- `crystal` no-codegen builds for:
  - `benchmarks/framework_performance_profile.cr`
  - `benchmarks/framework_performance_lab.cr`
- `acrystal` no-codegen build for:
  - `benchmarks/framework_performance_profile.cr`

## Focused Profile Read

The release-built profile harness was used for the decision because it remains
the most stable local measurement path on this machine.

### `crystal`

- validated query params average: `1,718,316`
- compiled query params average: `1,997,949`
- compiled vs validated: `1.1627x` (`+16.3%`)

- validated JSON-body params average: `1,601,061.5`
- compiled JSON-body params average: `2,031,664.5`
- compiled vs validated: `1.2689x` (`+26.9%`)

### `acrystal`

- validated query params average: `1,063,425.5`
- compiled query params average: `1,174,220`
- compiled vs validated: `1.1042x` (`+10.4%`)

- validated JSON-body params average: `1,220,991.5`
- compiled JSON-body params average: `1,319,062.5`
- compiled vs validated: `1.0803x` (`+8.0%`)

## Practical Read

The plain-English version:

- the user instinct here was good
- simply caching a generic validation interpreter was not enough
- compiling the validation shape into a direct validator is better

This is the first version that actually behaves like a “ready at runtime”
validation path instead of a “slightly less expensive way to rebuild or
interpret rules.”

## Important Caveat

This prototype is intentionally narrower than the full runtime DSL:

- it targets simple required/optional field groups
- it does not yet support predicate blocks
- it is designed for top-level precompiled validator constants, not inline
  per-request DSL calls

That is okay for now, because this round was about testing the performance
theory, not finishing the full public API.

## Best Next Move

The next worthwhile step is to expand this direct generated path carefully:

- support more of the existing validation DSL without falling back to a generic
  interpreter
- benchmark a compile-time/controller-level API for common hot endpoints
- rerun the broader framework lab and then a hosted Amber `1.4` vs `v2` run
  once this path is promoted
