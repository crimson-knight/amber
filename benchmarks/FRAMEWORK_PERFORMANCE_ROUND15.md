# Framework Performance Round 15

## Verdict

Keep the measurement harness. Do not promote either production code experiment.

Round 15 moved away from validated params internals and looked at router/source
lookup plus response finalization/write-path behavior. This was the right next
slice: it shows where Amber still spends time outside validation, but the two
small production tweaks tested here were not stable enough to keep.

## Changed

- `benchmarks/framework_performance_profile.cr`
  - added focused profile scenarios for raw plaintext, controller plaintext,
    raw JSON, direct JSON, raw query lookup, route+query dispatch, and raw JSON
    body parsing
- `benchmarks/bin/framework_router_response_truth_round.rb`
  - added a repeated profile/lab runner for router, params-source, dispatch, and
    response comparisons

## Production Experiments Tested

Rejected responder cleanup:

- cached `context.response` locally in `set_response`
- read `content.body` once in `respond_with`
- changed named `set_response` calls to positional calls

Rejected params-source cleanup:

- detected `Amber::Router::Params` body source at wrapper initialization instead
  of lazily on first lookup

Both passed targeted specs on `crystal` and `acrystal`, but neither gave a clean
framework-wide performance win.

## Validation

Targeted specs after each production experiment:

```text
CRYSTAL_WORKERS=1 crystal spec spec/amber/controller spec/amber/router spec/amber/validations/params_spec.cr
531 examples, 0 failures

CRYSTAL_WORKERS=1 acrystal spec spec/amber/controller spec/amber/router spec/amber/validations/params_spec.cr
531 examples, 0 failures
```

Repeated standard Crystal baseline:

```text
ruby benchmarks/bin/framework_router_response_truth_round.rb \
  --compiler=crystal \
  --profile-duration=2 \
  --profile-repetitions=3 \
  --lab-warmup=0.5 \
  --lab-calc=0.75 \
  --lab-repetitions=3 \
  --output=benchmarks/results/framework_router_response_round15_baseline_crystal.json
```

## Baseline Read

The repeated lab baseline says:

| comparison | ratio |
| --- | ---: |
| plaintext action vs raw response | 0.9709x |
| direct JSON action vs raw response | 0.9765x |
| `respond_with` JSON vs direct JSON | 0.9550x |
| Amber query params lookup vs raw `HTTP::Params` | 0.6763x |
| controller params wrapper query action vs raw params action | 1.0104x |
| route+query dispatch vs direct controller action | 0.9076x |
| Amber JSON body params lookup vs raw `JSON.parse` | 0.5904x |
| JSON body dispatch vs params lookup | 0.2879x |

Plain English:

- simple response actions are close to raw Crystal already
- `respond_with` has a small but real cost versus direct JSON
- the params wrapper is still much slower than direct `HTTP::Params` for raw
  lookup, but that cost mostly disappears once wrapped in a controller action
- route+query dispatch still has meaningful overhead
- JSON body dispatch is the largest remaining local red flag in this slice

## Experiment Results

Responder cleanup, repeated lab versus baseline:

| comparison | baseline | candidate | relative |
| --- | ---: | ---: | ---: |
| plaintext action vs raw response | 0.9709x | 0.9725x | +0.2% |
| direct JSON action vs raw response | 0.9765x | 0.9728x | -0.4% |
| `respond_with` JSON vs direct JSON | 0.9550x | 0.9547x | -0.0% |
| Amber query params lookup vs raw `HTTP::Params` | 0.6763x | 0.6748x | -0.2% |
| controller params wrapper query action vs raw params action | 1.0104x | 0.9948x | -1.5% |
| route+query dispatch vs direct controller action | 0.9076x | 0.9217x | +1.5% |
| Amber JSON body params lookup vs raw `JSON.parse` | 0.5904x | 0.5885x | -0.3% |
| JSON body dispatch vs params lookup | 0.2879x | 0.1869x | -35.1% |

Params-source cleanup, repeated lab versus baseline:

| comparison | baseline | candidate | relative |
| --- | ---: | ---: | ---: |
| plaintext action vs raw response | 0.9709x | 0.9761x | +0.5% |
| direct JSON action vs raw response | 0.9765x | 0.9986x | +2.3% |
| `respond_with` JSON vs direct JSON | 0.9550x | 0.9507x | -0.4% |
| Amber query params lookup vs raw `HTTP::Params` | 0.6763x | 0.6829x | +1.0% |
| controller params wrapper query action vs raw params action | 1.0104x | 1.0617x | +5.1% |
| route+query dispatch vs direct controller action | 0.9076x | 0.8779x | -3.3% |
| Amber JSON body params lookup vs raw `JSON.parse` | 0.5904x | 0.5908x | +0.1% |
| JSON body dispatch vs params lookup | 0.2879x | 0.1940x | -32.6% |

## Read

This round points us away from tiny helper cleanup and toward larger dispatch
and JSON-body work.

The next strongest bets are:

- profile `Amber::Pipe::Pipeline#call` and `Amber::Pipe::Controller#call`
- split JSON body dispatch into parse cost, controller construction, route
  dispatch, and response finalization
- run the same scenarios through local HTTP pressure with `oha`, then repeat on
  dedicated hardware once the local harness is stable
- only revisit `Params#[]?` if we can preserve route/query/body precedence while
  avoiding repeated source checks in routed requests
