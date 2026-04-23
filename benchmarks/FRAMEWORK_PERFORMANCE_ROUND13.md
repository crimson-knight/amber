# Framework Performance Round 13

## Verdict

Do not promote this change.

Round 13 tested a small hot-path allocation idea: when a validation definition
already knows how many params it may write, initialize the validated params Hash
with that capacity instead of starting from an empty default Hash.

The idea stayed compatible and passed the targeted specs on both `crystal` and
`acrystal`, but the repeated `crystal` truth run rejected it. It helped one
JSON-body case, stayed roughly flat in a few places, and badly hurt the hybrid
query focused profile. That is not stable enough for a framework default.

## Changed

- `src/amber/validators/params.cr`
  - added `validated_param_capacity`
  - initialized the validated params Hash with `initial_capacity` when a
    reusable definition or dynamic rule list already exposes a rule count

## Validation

Targeted compatibility specs:

```text
CRYSTAL_WORKERS=1 crystal spec spec/amber/validations/params_spec.cr spec/amber/controller/schema_integration_spec.cr
44 examples, 0 failures

CRYSTAL_WORKERS=1 acrystal spec spec/amber/validations/params_spec.cr spec/amber/controller/schema_integration_spec.cr
44 examples, 0 failures
```

Repeated standard Crystal truth run:

```text
ruby benchmarks/bin/framework_validation_truth_round.rb \
  --compiler=crystal \
  --profile-duration=6 \
  --profile-repetitions=5 \
  --lab-warmup=1 \
  --lab-calc=2 \
  --lab-repetitions=4 \
  --output=benchmarks/results/framework_validation_truth_round13_crystal.json
```

Result:

```text
Verdict: reject - The repeated focused profile did not support a clean
across-the-board win strongly enough to promote this path.
```

## Results

Focused profile, standard Crystal:

| comparison | Round 11 | Round 13 | relative |
| --- | ---: | ---: | ---: |
| query simple compiled vs validated | 1.3428x | 1.3247x | -1.3% |
| query hybrid compiled vs mixed | 1.2904x | 0.8775x | -32.0% |
| query predicate-only compiled vs validated | 1.0065x | 0.9970x | -0.9% |
| JSON-body simple compiled vs validated | 1.0653x | 1.2061x | +13.2% |
| JSON-body hybrid compiled vs mixed | 1.1291x | 1.1448x | +1.4% |

Filtered framework lab, standard Crystal:

| comparison | Round 13 |
| --- | ---: |
| query compiled vs validated | 1.0960x |
| query hybrid vs mixed | 1.0860x |
| JSON-body compiled vs validated | 1.0655x |
| JSON-body hybrid vs mixed | 1.0761x |

## Read

This is a good example of an optimization that is locally plausible but not
good enough as a framework default. Hash pre-sizing may help when body parsing
or object shape dominates, but it can make small query validations slower. Since
Amber needs predictable wins across normal endpoint shapes, this round should
stay as research evidence only.

The more promising next move is not a smaller Hash; it is removing the Hash
from hot validated success paths when the app opts into a compiled validation
mode that can safely read directly from already-validated raw params.
