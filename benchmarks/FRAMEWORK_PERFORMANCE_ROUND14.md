# Framework Performance Round 14

## Verdict

Do not promote this API shape.

Round 14 tested the stronger version of the Round 13 lesson: if the validated
Hash is still suspicious, can hot endpoints skip materializing it entirely?

Two things were tested:

- an opt-in `ensure_valid!(definition)` API that validates a reusable definition
  without building the validated params Hash
- benchmark-only one-pass floor scenarios that validate and consume values in
  the same hand-written controller path

The compatibility checks passed on both `crystal` and `acrystal`, but the
standard Crystal smoke runs rejected the optimization. `ensure_valid!` mostly
lost because it has to reread values from `raw_params`, and those raw lookups are
not cheaper than reading the small validated Hash. The hand-written one-pass
floor also hovered around flat, which suggests the accepted compiled validation
path is already close to the local in-process floor for these small validation
shapes.

## Changed

- `src/amber/validators/params.cr`
  - added validation-only reusable definition application
  - added `Params#ensure_valid!(definition)`
  - added `Params#valid?(definition)`
- `spec/amber/validations/params_spec.cr`
  - covered compiled and reusable validation-only success/failure behavior
- `benchmarks/framework_performance_profile.cr`
  - added `ensure_valid!` scenarios
  - added benchmark-only one-pass floor scenarios
- `benchmarks/framework_performance_lab.cr`
  - added matching lab scenarios and comparisons
- `benchmarks/bin/framework_validation_truth_round.rb`
  - added focused/lab comparisons for `ensure_valid!`
  - added focused/lab comparisons for benchmark-only one-pass floor scenarios

## Validation

Targeted compatibility specs:

```text
CRYSTAL_WORKERS=1 crystal spec spec/amber/validations/params_spec.cr spec/amber/controller/schema_integration_spec.cr
47 examples, 0 failures

CRYSTAL_WORKERS=1 acrystal spec spec/amber/validations/params_spec.cr spec/amber/controller/schema_integration_spec.cr
47 examples, 0 failures
```

Standard Crystal smoke, `ensure_valid!` only:

```text
benchmarks/results/framework_validation_truth_round14_smoke_crystal.json
Verdict: reject
```

Standard Crystal smoke with one-pass floor scenarios:

```text
benchmarks/results/framework_validation_truth_round14_floor_smoke_crystal.json
Verdict: reject
```

## Results

Smoke profile medians, `ensure_valid!` or one-pass floor versus the accepted
compiled `validate!` path:

| comparison | median |
| --- | ---: |
| query simple `ensure_valid!` | 0.9929x |
| query simple one-pass floor | 0.9518x |
| query hybrid `ensure_valid!` | 1.0611x |
| query hybrid one-pass floor | 0.8861x |
| JSON-body simple `ensure_valid!` | 1.1844x |
| JSON-body simple one-pass floor | 1.1240x |
| JSON-body hybrid `ensure_valid!` | 1.1714x |
| JSON-body hybrid one-pass floor | 1.0727x |

Smoke lab medians, same comparison:

| comparison | median |
| --- | ---: |
| query simple `ensure_valid!` | 0.9850x |
| query simple one-pass floor | 1.0030x |
| query hybrid `ensure_valid!` | 0.9936x |
| query hybrid one-pass floor | 1.0038x |
| JSON-body simple `ensure_valid!` | 0.9671x |
| JSON-body simple one-pass floor | 0.9529x |
| JSON-body hybrid `ensure_valid!` | 0.9811x |
| JSON-body hybrid one-pass floor | 0.9860x |

## Read

This round changes the mental model.

The earlier guess was: "the Hash is the remaining enemy." The better read is:
"the current compiled Hash path is already cheap, and raw params source lookup
is expensive enough that avoiding the Hash does not automatically win."

For this validation slice, a reasonable local floor is about 4 microseconds per
tiny validated controller action on this machine. Chasing another large win here
probably requires a different contract, such as generated typed request structs,
or shifting attention to router/source lookup, response writing, JSON
serialization, and full HTTP pressure tests.
