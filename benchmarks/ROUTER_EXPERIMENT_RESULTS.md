# Router Experiment Results

These results were measured on branch `experiment/router-performance-lab`
using release builds of `benchmarks/router_strategy_compare.cr` at tiers
`100, 1000, 5000, 10000` with `--warmup=1 --calc=1`.

## Execution flow

Because the local macOS environment was inconsistent about launching binaries
built and executed in the same process, the reliable path was:

```bash
bash benchmarks/bin/router_strategy_build.sh --compiler crystal --output /tmp/router_strategy_compare.crystal
AMBER_BENCH_COMPILER=/opt/homebrew/bin/crystal /tmp/router_strategy_compare.crystal --tiers=100,1000,5000,10000 --warmup=1 --calc=1
```

The same flow was used for `acrystal`.

## Checkpoints

### V1

- Baseline experiment harness plus `find_experimental_best`
- Results:
  - `crystal`: mean `1.329x`, geometric mean `1.314x`
  - `acrystal`: mean `1.357x`, geometric mean `1.334x`

### V2

- Cached segment parameter names
- Decoded path params only when the value actually contains escape sequences
- Results:
  - `crystal`: mean `1.354x`, geometric mean `1.336x`
  - `acrystal`: mean `1.346x`, geometric mean `1.327x`

### V3

- Made `RoutedResult` params lazy so fixed and not-found matches do not pay for
  an unused hash
- Results:
  - `crystal`: mean `1.355x`, geometric mean `1.333x`
  - `acrystal`: mean `1.356x`, geometric mean `1.334x`

### V4

- Precomputed the minimum route priority reachable from each subtree
- Pruned experimental matcher branches that cannot beat the current winner
- Results:
  - `crystal`: mean `1.709x`, geometric mean `1.555x`
  - `acrystal`: mean `1.726x`, geometric mean `1.556x`

V4 is the current best checkpoint.

Important translation:

- `1.33x` means `33%` faster than the baseline
- `1.55x` means `55%` faster than the baseline
- `55.7x` means `5470%` faster than the baseline

The big clarification is that the older `55.7x` result and the newer `1.55x`
result are measuring different things. The `55.7x` number is the historical
glob improvement from the original `amber_router` shard to the internalized
Amber V2 engine at `10,000` routes. The `1.55x` number is the latest
incremental gain from `current_find` to `experimental_best` inside the already
optimized Amber V2 engine.

## Historical Context

The older `1.3x-55.7x` claim came from a different comparison:

- baseline: the original `amber_router` shard (`benchmarks/results/baseline_expanded.json`)
- optimized: the internalized Amber V2 routing engine (`benchmarks/results/final_expanded.json`)

That historical benchmark is where the major glob wins came from:

- `100` routes: fixed `1.31x`, variable `1.26x`, glob `1.41x`, notfound `1.85x`
- `5000` routes: fixed `1.41x`, variable `1.66x`, glob `27.36x`, notfound `1.86x`
- `10000` routes: fixed `1.60x`, variable `1.85x`, glob `55.70x`, notfound `1.76x`

The current experiment is measuring something narrower: whether a
best-match traversal plus a few allocation reductions can beat the already
optimized Amber V2 matcher.

## Before And After

Comparing the experimental matcher at `10,000` routes from V1 to V3:

### `crystal`

- fixed: `3.85M -> 4.59M IPS` (`+19.3%`)
- variable: `4.91M -> 5.38M IPS` (`+9.5%`)
- glob: `2.08M -> 2.35M IPS` (`+12.6%`)
- notfound: `4.38M -> 4.95M IPS` (`+13.0%`)

### `acrystal`

- fixed: `3.12M -> 3.67M IPS` (`+17.5%`)
- variable: `4.10M -> 4.39M IPS` (`+7.1%`)
- glob: `1.76M -> 1.91M IPS` (`+8.2%`)
- notfound: `3.64M -> 4.12M IPS` (`+13.0%`)

## Practical Range

The more useful comparison for mature applications is the `500-1500` route
range. Across those tiers, V4 versus the original matcher came out to:

### `crystal`

- overall: mean `1.632x`, geometric mean `1.523x`
- `500` routes:
  - fixed: `3.04M -> 8.35M IPS` (`+174.4%`)
  - variable: `4.00M -> 5.90M IPS` (`+47.4%`)
  - glob: `2.03M -> 2.60M IPS` (`+28.5%`)
  - notfound: `5.00M -> 5.14M IPS` (`+2.7%`)
- `1000` routes:
  - fixed: `3.17M -> 8.67M IPS` (`+173.1%`)
  - variable: `4.27M -> 6.48M IPS` (`+51.9%`)
  - glob: `2.24M -> 2.78M IPS` (`+23.9%`)
  - notfound: `5.20M -> 5.63M IPS` (`+8.4%`)
- `1500` routes:
  - fixed: `3.20M -> 8.69M IPS` (`+171.5%`)
  - variable: `4.44M -> 6.36M IPS` (`+43.2%`)
  - glob: `2.19M -> 2.80M IPS` (`+27.8%`)
  - notfound: `5.31M -> 5.61M IPS` (`+5.6%`)

### `acrystal`

- overall: mean `1.648x`, geometric mean `1.525x`
- `500` routes:
  - fixed: `3.10M -> 8.57M IPS` (`+176.5%`)
  - variable: `4.10M -> 5.99M IPS` (`+46.1%`)
  - glob: `2.06M -> 2.64M IPS` (`+28.2%`)
  - notfound: `5.19M -> 5.30M IPS` (`+2.2%`)
- `1000` routes:
  - fixed: `2.80M -> 8.21M IPS` (`+193.5%`)
  - variable: `3.78M -> 5.54M IPS` (`+46.6%`)
  - glob: `2.02M -> 2.37M IPS` (`+17.3%`)
  - notfound: `4.64M -> 4.85M IPS` (`+4.5%`)
- `1500` routes:
  - fixed: `2.84M -> 7.98M IPS` (`+180.4%`)
  - variable: `3.96M -> 5.77M IPS` (`+45.6%`)
  - glob: `1.95M -> 2.54M IPS` (`+29.8%`)
  - notfound: `4.85M -> 5.17M IPS` (`+6.6%`)

## Derived Cumulative View

If we stitch the historical shard benchmark together with the current V4
experiment, the cumulative story is stronger than the raw `1.55x` lab summary
suggests. This is a **derived comparison**, not a single-run benchmark, because
the historical and current files were not recorded in the same session.

### `crystal`

- `100` routes:
  - fixed `2.55M -> 9.22M` (`3.61x`)
  - variable `3.54M -> 6.70M` (`1.89x`)
  - glob `1.64M -> 2.74M` (`1.67x`)
  - notfound `3.06M -> 5.65M` (`1.85x`)
- `5000` routes:
  - fixed `1.82M -> 7.23M` (`3.97x`)
  - variable `2.16M -> 4.60M` (`2.13x`)
  - glob `67K -> 2.14M` (`31.71x`)
  - notfound `2.45M -> 4.44M` (`1.81x`)
- `10000` routes:
  - fixed `1.51M -> 7.33M` (`4.85x`)
  - variable `1.79M -> 5.09M` (`2.84x`)
  - glob `31K -> 2.19M` (`70.29x`)
  - notfound `2.37M -> 4.70M` (`1.98x`)

### `acrystal`

- `100` routes:
  - fixed `2.55M -> 9.28M` (`3.64x`)
  - variable `3.54M -> 6.67M` (`1.88x`)
  - glob `1.64M -> 2.64M` (`1.60x`)
  - notfound `3.06M -> 5.55M` (`1.82x`)
- `5000` routes:
  - fixed `1.82M -> 7.32M` (`4.02x`)
  - variable `2.16M -> 4.72M` (`2.18x`)
  - glob `67K -> 2.13M` (`31.54x`)
  - notfound `2.45M -> 4.40M` (`1.80x`)
- `10000` routes:
  - fixed `1.51M -> 6.45M` (`4.27x`)
  - variable `1.79M -> 4.27M` (`2.38x`)
  - glob `31K -> 1.82M` (`58.20x`)
  - notfound `2.37M -> 3.83M` (`1.62x`)

## Benchmark Reconciliation

To regenerate the progression from the stored JSON snapshots:

```bash
ruby benchmarks/bin/router_result_reconcile.rb
```

That script prints:

- historical measured gains: old shard -> internalized engine
- current measured gains: `current_find` -> `experimental_best`
- derived cumulative gains: old shard -> `experimental_best`

## Current Recommendation

- Keep the experimental best-match traversal as the leading candidate.
- Keep the subtree minimum-priority pruning added in V4.
- Keep the cached segment parameters and lazy `RoutedResult` params changes.
- Prefer the build-then-run benchmark flow when validating locally across both
  `crystal` and `acrystal`.
- Next research target: remove request-time `split_path` work from the lookup
  hot path so we are not paying for a new segment array on every request.
