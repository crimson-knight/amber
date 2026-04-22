# Amber Performance Change Log

This file is the durable benchmark ledger for Amber V2 performance work.

For each kept change, record:

- the checkpoint commit
- the hypothesis
- the files changed
- the measured impact
- whether the result is local-lab only or backed by an external hosted run

## Historical Baseline Story

### Router Internalization

- baseline: original `amber_router` shard
- optimized engine: internalized Amber V2 router
- canonical note: `benchmarks/ROUTER_EXPERIMENT_RESULTS.md`

Historical measured gains from that earlier router rewrite:

- `100` routes: fixed `1.31x`, variable `1.26x`, glob `1.41x`, notfound `1.85x`
- `5000` routes: fixed `1.41x`, variable `1.66x`, glob `27.36x`, notfound `1.86x`
- `10000` routes: fixed `1.60x`, variable `1.85x`, glob `55.70x`, notfound `1.76x`

This is the source of the well-remembered `55.7x` result. It is not the same
baseline as the newer framework-lab rounds.

### Hosted Amber 1.4 vs Amber V2

- hosted comparison note:
  `/Users/crimsonknight/open_source_coding_projects/FrameworkBenchmarks/frameworks/Crystal/AMBER_V1_V2_DO_RESULTS_2026-04-21.md`
- benchmarked Amber V2 snapshot: router-focused vendor snapshot at commit
  `790c7a8d5926ae69d8f3b565a7d63005d45d4f89`

Hosted measured gains versus Amber `1.4`:

- `json`: mean `1.108x`, geometric mean `1.107x`
- `plaintext`: mean `1.566x`, geometric mean `1.562x`

Important caveat:

- this hosted run predates the later framework-lab rounds below
- a new hosted rerun is still needed to measure the full compounded effect of
  the controller/dispatch/write-path changes that landed afterward

## Framework Lab Timeline

### Base

- benchmark base commit: `c7b7069`
- note: `benchmarks/FRAMEWORK_PERFORMANCE_HYPOTHESES.md`

Initial baseline read:

- controller param access was roughly `4.3x-4.5x` slower than direct Amber
  params lookup
- Amber JSON body params were roughly `3.2x` slower than raw JSON parse
- Amber JSON-body dispatch was roughly `3.1x` slower than params lookup

### Round 1

- promoted checkpoint: `e1a75e7`
- note: `benchmarks/FRAMEWORK_PERFORMANCE_PARALLEL_RESULTS.md`

Hypotheses promoted:

- params fast paths
- controller param laziness

Key measured wins:

- `amber_params_lookup_query`
  - `crystal`: `831k -> 1.087M` (`+30.7%`)
  - `acrystal`: `884k -> 1.103M` (`+24.8%`)
- `amber_params_lookup_json`
  - `crystal`: `485k -> 879k` (`+81.2%`)
  - `acrystal`: `508k -> 885k` (`+74.3%`)
- `amber_dispatch_json_body`
  - `crystal`: `157k -> 188k` (`+19.3%`)
  - `acrystal`: `161k -> 169k` (`+5.3%`)

### Round 2

- promoted checkpoint: `4e6922d`
- note: `benchmarks/FRAMEWORK_PERFORMANCE_ROUND2.md`

Hypothesis promoted:

- lazy `Amber::Validators::Params` on the read-only path

Key measured wins versus Round 1:

- `amber_action_query_params`
  - `crystal`: `188,857 -> 217,305` (`+15.1%`)
  - `acrystal`: `202,055 -> 231,442` (`+14.5%`)
- `amber_dispatch_json`
  - `crystal`: `213,648 -> 259,263` (`+21.4%`)
  - `acrystal`: `196,183 -> 277,922` (`+41.7%`)
- `amber_dispatch_plaintext`
  - `crystal`: `250,285 -> 280,859` (`+12.2%`)
  - `acrystal`: `267,502 -> 298,469` (`+11.6%`)

### Round 3

- promoted checkpoint: `4b8b1ac`
- note: `benchmarks/FRAMEWORK_PERFORMANCE_ROUND3.md`

Hypotheses promoted:

- dispatch bookkeeping cleanup
- POST-only request-method caching

Rejected:

- broader response output/content-length fast path

Key measured wins versus Round 2:

- `amber_dispatch_plaintext`
  - `crystal`: `280,859 -> 297,485` (`+5.9%`)
- `amber_dispatch_json`
  - `crystal`: `259,263 -> 264,478` (`+2.0%`)
- `amber_dispatch_json_body`
  - `crystal`: `189,481 -> 314,849` (`+66.2%`)

### Round 4

- promoted checkpoint: `cc35587`
- note: `benchmarks/FRAMEWORK_PERFORMANCE_ROUND4.md`

Hypotheses promoted:

- single-response `respond_with` fast path
- specialized `String`/`Symbol` hot-param overloads

Key measured wins versus the same-session Round 4 control:

- `amber_action_json_direct`: `291,522 -> 308,956` (`+6.0%`)
- `amber_action_json_respond_with`: `266,836 -> 296,624` (`+11.2%`)
- `amber_dispatch_json`: `248,100 -> 261,172` (`+5.3%`)
- `amber_action_query_params`: `204,378 -> 217,151` (`+6.2%`)
- `amber_dispatch_json_body`: `279,783 -> 295,652` (`+5.7%`)

Compounded effect versus the original framework baseline:

- `crystal`: six-hotspot mean `1.487x`, geometric mean `1.446x`

### Round 5

- branch base: `experiment/framework-performance-writepath-round5`
- note: `benchmarks/FRAMEWORK_PERFORMANCE_ROUND5.md`

Kept:

- explicit raw-vs-validated controller scenarios in the framework lab
- expanded profile scenarios for responder/write-path investigation
- durable benchmark ledger in this file

Rejected:

- narrower write-path/content-length fast path

Key measured read:

- wrapper-only query param access is already close to raw (`0.984x`)
- validated query params vs raw measured `0.872x`
- validated JSON body params vs raw measured `0.941x`

That means the current wrapper itself is not the main problem anymore; the
heavier cost is the validation step.

### Round 6

- branch base: `experiment/framework-performance-validation-round6`
- note: `benchmarks/FRAMEWORK_PERFORMANCE_ROUND6.md`

Rejected:

- validation-rule micro-optimization that removed duplicate lookups and the
  default no-op predicate call

Why it did not advance:

- same-harness lab results were mixed
- targeted profile runs flipped direction depending on run order
- the measured signal was not stable enough to justify promotion

Useful takeaway:

- validation is still a real target
- the next worthwhile version is likely a larger structural change such as
  compiled or cached validation definitions, not a tiny rule-evaluation tweak

## Recording Rule Going Forward

When a new round lands, append:

1. commit hash
2. short hypothesis summary
3. files changed
4. crystal same-session deltas
5. acrystal deltas if trustworthy, otherwise note them as provisional
6. whether an external hosted rerun has confirmed the change yet
