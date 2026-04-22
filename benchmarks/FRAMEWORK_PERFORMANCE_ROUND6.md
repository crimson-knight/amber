# Framework Performance Round 6

Round 6 tested a small validation-path cleanup in `Amber::Validators::Params`
 and `BaseRule`:

- stop routing no-block rules through a default proc call
- stop re-reading the same param value multiple times inside one rule

## Verdict

Reject the runtime change.

The idea was good, but the measured result did not settle into a clean,
trustworthy win on this machine.

## What Was Tested

The candidate branch changed `src/amber/validators/params.cr` to:

- read each rule value once
- skip the default predicate proc call when no validation block exists
- preserve compatibility behavior for required and optional rules

Validation and compatibility checks passed:

- `spec/amber/validations/params_spec.cr`
- `spec/amber/controller/schema_integration_spec.cr`
- no-codegen builds for `framework_performance_lab` and
  `framework_performance_profile`
- `acrystal` no-codegen builds for the same targets

## Same-Harness Lab Read

Control files:

- `benchmarks/results/framework_performance_lab_round5_control_round6_crystal.json`
- `benchmarks/results/framework_performance_lab_round5_control_round6_acrystal.json`

Candidate files:

- `benchmarks/results/framework_performance_lab_round6_crystal.json`
- `benchmarks/results/framework_performance_lab_round6_acrystal.json`

### `crystal`

The intended validation paths were mixed:

- `amber_action_query_validated_params`: `173,336 -> 175,804` IPS (`+1.4%`)
- `amber_action_json_body_validated_params`: `188,760 -> 170,166` IPS (`-9.9%`)

Non-validation paths also moved around more than they should have for such a
small change:

- `amber_dispatch_json`: `196,097 -> 245,221` IPS (`+25.1%`)
- `amber_dispatch_json_body`: `221,237 -> 172,017` IPS (`-22.2%`)

That is a red flag. A change this narrow should not swing unrelated scenarios so
hard unless the environment is noisy.

### `acrystal`

`acrystal` looked much stronger:

- `amber_action_query_validated_params`: `116,833 -> 204,501` IPS (`+75.0%`)
- `amber_action_json_body_validated_params`: `139,038 -> 189,895` IPS (`+36.6%`)

But those jumps are too large to trust by themselves when the same machine is
already showing instability on nearby scenarios.

## Targeted Profile Read

I also ran the release-built profile harness directly against the validated
scenarios to get a second opinion.

First run order:

- query validated:
  - control `1,842,581`
  - candidate `1,378,514`
- JSON-body validated:
  - control `1,162,110`
  - candidate `1,856,942`

Reversed run order:

- query validated:
  - candidate `1,487,669`
  - control `1,461,985`
- JSON-body validated:
  - candidate `1,313,290`
  - control `1,343,094`

That tells the story pretty clearly: the machine noise is large enough that
this patch does not earn promotion.

## Practical Read

The validation path is still a worthwhile target, but this specific cleanup is
too small and too noisy to treat as a real framework improvement.

The next better validation experiment is probably a bigger structural one:

- reduce or eliminate per-request rule object allocation
- cache compiled validation definitions for hot actions
- measure that with the validated scenarios added in Round 5
