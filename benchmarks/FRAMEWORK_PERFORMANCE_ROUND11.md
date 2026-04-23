# Framework Performance Round 11

Round 11 was the “truth round.”

The goal was not to invent another runtime trick. The goal was to settle the
Round 10 disagreement between:

- the short full framework lab, which said the compiled validation path looked
  better
- the focused validation profile, which still looked noisy and contradictory

## Verdict

Keep the direction.

Round 11 finally gave us a cleaner read on the same Round 10 runtime slice. The
important compiled and hybrid validation comparisons stayed positive across both
compilers when we switched from one-off samples to repeated alternating-order
medians.

One nuance matters:

- the core compiled and hybrid validation comparisons held up
- the predicate-only query isolator on stock `crystal` is still noisy and only
  barely positive on the median, so it should stay a diagnostic scenario, not a
  promotion gate by itself

## What Changed

Files:

- `benchmarks/framework_performance_lab.cr`
- `benchmarks/bin/framework_profile_build.sh`
- `benchmarks/bin/framework_validation_truth_round.rb`

Main implementation points:

- added a `--scenarios=` filter to the framework lab so Round 11 can run only
  the validation slice instead of the whole suite
- added a dedicated profile build helper so the truth runner can build the
  focused harness the same way the lab build already works
- added a Round 11 truth runner that:
  - builds both binaries once
  - warms the focused scenarios
  - runs paired focused comparisons in alternating order
  - repeats the filtered framework lab several times
  - records medians, spread, and a verdict in one JSON artifact

## Validation Status

Passed:

- `CRYSTAL_WORKERS=1 crystal build --error-trace --no-codegen benchmarks/framework_performance_lab.cr`
- `CRYSTAL_WORKERS=1 acrystal build --error-trace --no-codegen benchmarks/framework_performance_lab.cr`
- `ruby -c benchmarks/bin/framework_validation_truth_round.rb`
- `bash benchmarks/bin/framework_profile_build.sh --compiler crystal --output /tmp/amber-round11-profile-build-check`

Notes:

- the only build output was the existing deprecated `File.readable?` warning in
  Amber support code

## Round 11 Run Shape

Local truth-run settings:

- focused profile:
  - `--profile-duration=6`
  - `--profile-repetitions=5`
  - one-time warmup of `0.75s` per scenario
- filtered framework lab:
  - `--lab-warmup=1`
  - `--lab-calc=2`
  - `--lab-repetitions=4`
  - validation scenarios only

Canonical files:

- `benchmarks/results/framework_validation_truth_round11_crystal.json`
- `benchmarks/results/framework_validation_truth_round11_acrystal.json`

## Results

### `crystal`

Focused profile medians:

- simple query compiled vs runtime validated: `1.3428x`
- hybrid query compiled vs mixed runtime validated: `1.2904x`
- predicate-only query compiled vs runtime validated: `1.0065x`
- simple JSON-body compiled vs runtime validated: `1.0653x`
- hybrid JSON-body compiled vs mixed runtime validated: `1.1291x`

Filtered framework-lab medians:

- query compiled vs validated: `1.0936x`
- query hybrid vs mixed: `1.0974x`
- JSON-body compiled vs validated: `1.0740x`
- JSON-body hybrid vs mixed: `1.0478x`

### `acrystal`

Focused profile medians:

- simple query compiled vs runtime validated: `1.2590x`
- hybrid query compiled vs mixed runtime validated: `1.1232x`
- predicate-only query compiled vs runtime validated: `1.1498x`
- simple JSON-body compiled vs runtime validated: `1.3149x`
- hybrid JSON-body compiled vs mixed runtime validated: `1.3262x`

Filtered framework-lab medians:

- query compiled vs validated: `1.0900x`
- query hybrid vs mixed: `1.0900x`
- JSON-body compiled vs validated: `1.0711x`
- JSON-body hybrid vs mixed: `1.0535x`

## Practical Read

The plain-English version:

- Round 10 looked split because we were comparing thin single-sample reads
- Round 11 reran the same idea with repeated medians and much cleaner
  comparison discipline
- once we did that, the important compiled validation paths held up on both
  compilers

That is enough for me to treat the Round 10 runtime slice as a real keep.

The one thing I would still *not* oversell is the predicate-only query case on
stock `crystal`. It came out slightly positive on the median, but only `3/5`
profile samples were directionally positive. That makes it useful as a
diagnostic canary, not the headline win.

## Best Next Move

The next step should be a quiet hosted confirmation, not another local rewrite.

The smallest practical hosted version is:

- one dedicated CPU DigitalOcean droplet
- copy the Amber perf worktree there
- install both `crystal` and `acrystal`
- rerun this same Round 11 truth script with longer durations and more repeats
- pull back the JSON artifacts and destroy the droplet

That gives us the cleanest path to a stronger “yes, this survives off the
laptop too” confirmation without dragging in a full multi-host TechEmpower
cluster.
