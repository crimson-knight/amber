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

## Current Recommendation

- Keep the experimental best-match traversal as the leading candidate.
- Keep the cached segment parameters and lazy `RoutedResult` params changes.
- Prefer the build-then-run benchmark flow when validating locally across both
  `crystal` and `acrystal`.
