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

V2 had the best relative ratio on stock `crystal`, but V3 produced the best
absolute throughput overall while keeping both compilers closely aligned.

The important clarification is that the big gain is **V3 versus the original
`current_find` matcher**, not V2 versus V3. V2 to V3 is incremental. Original
to V3 is the large step.

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
range. Across those tiers, V3 versus the original matcher came out to:

### `crystal`

- overall: mean `1.375x`, geometric mean `1.354x`
- `500` routes:
  - fixed: `3.02M -> 5.24M IPS` (`+73.3%`)
  - variable: `4.35M -> 6.19M IPS` (`+42.3%`)
  - glob: `2.18M -> 2.73M IPS` (`+25.2%`)
  - notfound: `4.93M -> 5.57M IPS` (`+12.9%`)
- `1000` routes:
  - fixed: `2.95M -> 4.94M IPS` (`+67.7%`)
  - variable: `4.10M -> 5.74M IPS` (`+40.1%`)
  - glob: `2.05M -> 2.45M IPS` (`+19.6%`)
  - notfound: `4.95M -> 5.15M IPS` (`+4.0%`)
- `1500` routes:
  - fixed: `3.26M -> 5.55M IPS` (`+70.6%`)
  - variable: `3.93M -> 6.20M IPS` (`+57.8%`)
  - glob: `2.13M -> 2.75M IPS` (`+29.2%`)
  - notfound: `5.27M -> 5.65M IPS` (`+7.1%`)

### `acrystal`

- overall: mean `1.368x`, geometric mean `1.347x`
- `500` routes:
  - fixed: `2.96M -> 5.17M IPS` (`+74.8%`)
  - variable: `4.34M -> 6.02M IPS` (`+38.8%`)
  - glob: `2.17M -> 2.71M IPS` (`+24.9%`)
  - notfound: `4.99M -> 5.70M IPS` (`+14.1%`)
- `1000` routes:
  - fixed: `2.86M -> 4.74M IPS` (`+65.8%`)
  - variable: `4.02M -> 5.65M IPS` (`+40.4%`)
  - glob: `2.02M -> 2.38M IPS` (`+17.9%`)
  - notfound: `4.99M -> 5.09M IPS` (`+2.0%`)
- `1500` routes:
  - fixed: `3.19M -> 5.47M IPS` (`+71.3%`)
  - variable: `3.94M -> 6.23M IPS` (`+58.2%`)
  - glob: `2.13M -> 2.70M IPS` (`+27.0%`)
  - notfound: `5.40M -> 5.76M IPS` (`+6.7%`)

## Current Recommendation

- Keep the experimental best-match traversal as the leading candidate.
- Keep the cached segment parameters and lazy `RoutedResult` params changes.
- Prefer the build-then-run benchmark flow when validating locally across both
  `crystal` and `acrystal`.
