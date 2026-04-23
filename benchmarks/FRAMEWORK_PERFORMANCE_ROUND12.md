# Framework Performance Round 12

Round 12 tested one focused runtime hypothesis:

- successful compiled validation still pays for error handling setup even when
  there is no validation failure
- make error collection lazy so success-path validation only allocates an error
  array when an error is actually recorded

## Verdict

Do **not** promote this runtime change.

This round did not fail. The Round 11 truth harness still came back `keep` on
both compilers. But when compared directly against Round 11, the gains mostly
shifted around instead of clearly improving.

That means this branch is a useful checkpoint, but not a strong enough runtime
upgrade to stack into the promoted performance line.

## What Changed

Files:

- `src/amber/validators/params.cr`

Main implementation point:

- replaced eager `Array(Error)` usage in the validation hot path with a lazy
  `ErrorBuffer` so compiled and reusable validation paths only allocate the
  underlying error array when an error is actually appended

## Validation Status

Passed:

- `CRYSTAL_WORKERS=1 crystal spec spec/amber/validations/params_spec.cr spec/amber/controller/schema_integration_spec.cr`
  - `44 examples, 0 failures`
- `CRYSTAL_WORKERS=1 crystal build --error-trace --no-codegen benchmarks/framework_performance_lab.cr`
- `CRYSTAL_WORKERS=1 acrystal build --error-trace --no-codegen benchmarks/framework_performance_lab.cr`
- `CRYSTAL_WORKERS=1 crystal build --error-trace --no-codegen benchmarks/framework_performance_profile.cr`
- `CRYSTAL_WORKERS=1 acrystal build --error-trace --no-codegen benchmarks/framework_performance_profile.cr`
- Round 11 truth harness rerun on Round 12 code for both compilers

Notes:

- the only build output was the existing deprecated `File.readable?` warning in
  Amber support code

## Canonical Files

- `benchmarks/results/framework_validation_truth_round12_crystal.json`
- `benchmarks/results/framework_validation_truth_round12_acrystal.json`

## Results

### Absolute Read

The repeated truth harness still returned `keep` on both compilers, which means
the validation direction itself remained sound:

### `crystal`

- focused profile medians:
  - simple query: `1.2215x`
  - hybrid query: `1.1936x`
  - predicate-only query: `1.0798x`
  - simple JSON body: `1.2334x`
  - hybrid JSON body: `1.3452x`
- filtered framework-lab medians:
  - query compiled vs validated: `1.1079x`
  - query hybrid vs mixed: `1.0818x`
  - JSON-body compiled vs validated: `1.0708x`
  - JSON-body hybrid vs mixed: `1.0509x`

### `acrystal`

- focused profile medians:
  - simple query: `1.1464x`
  - hybrid query: `1.2118x`
  - predicate-only query: `1.0428x`
  - simple JSON body: `1.1425x`
  - hybrid JSON body: `1.0690x`
- filtered framework-lab medians:
  - query compiled vs validated: `1.0941x`
  - query hybrid vs mixed: `1.0886x`
  - JSON-body compiled vs validated: `1.0766x`
  - JSON-body hybrid vs mixed: `1.0719x`

### Relative Read Versus Round 11

This is the part that mattered for promotion.

On `crystal`, Round 12 improved the JSON-heavy focused profile cases, but the
query-focused profile cases got weaker:

- simple query median moved `1.3428x -> 1.2215x`
- hybrid query median moved `1.2904x -> 1.1936x`
- simple JSON-body median moved `1.0653x -> 1.2334x`
- hybrid JSON-body median moved `1.1291x -> 1.3452x`

On `acrystal`, the filtered framework lab was slightly better overall, but the
focused profile mostly moved sideways or down except for hybrid query:

- simple query median moved `1.2590x -> 1.1464x`
- hybrid query median moved `1.1232x -> 1.2118x`
- simple JSON-body median moved `1.3149x -> 1.1425x`
- hybrid JSON-body median moved `1.3262x -> 1.0690x`

## Practical Read

The plain-English version:

- the lazy error-buffer idea did not break the validation work
- it probably does help some success-path shapes
- but it did not produce a cleaner, stronger overall result than Round 11

That is not enough for me to keep the extra runtime complexity.

## Best Next Move

The better next round is probably not another tiny allocation tweak inside the
same validation core.

The higher-confidence path forward is:

- run the Round 11 truth harness on a quiet dedicated DigitalOcean host
- promote Round 11 itself into the main performance line
- then attack the next larger bottleneck, likely typed extraction or
  controller-level compile-time validation declarations, with the hosted truth
  harness ready from day one
