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

### Round 7

- branch base: `experiment/framework-performance-validation-cache-round7`
- note: `benchmarks/FRAMEWORK_PERFORMANCE_ROUND7.md`

Rejected for default promotion:

- compiled validation definitions via `Params.define`
- per-request reuse through `validation(definition)`

Why it did not advance:

- it helped validated JSON-body paths
- it hurt validated query-param paths
- the split showed up under both `crystal` and `acrystal`, so this looks like a
  real tradeoff instead of a clean across-the-board win

Key measured read from the focused profile harness:

- `crystal` query compiled vs validated: `0.8215x`
- `crystal` JSON-body compiled vs validated: `1.2527x`
- `acrystal` query compiled vs validated: `0.9429x`
- `acrystal` JSON-body compiled vs validated: `1.1302x`

Useful takeaway:

- caching validation definitions can help heavier validated request bodies
- a generic compiled-rule interpreter is not the right default answer
- the better next version is probably a more specialized or macro-generated
  validator path

### Round 8

- branch base: `experiment/framework-performance-validation-compiled-dsl-round8`
- note: `benchmarks/FRAMEWORK_PERFORMANCE_ROUND8.md`

Kept direction:

- direct generated compiled validators via `Params.compile NAME do ... end`
- reuse through `validation(compiled_definition)`

Phase 1 result:

- macro-generated proc-based validators were an improvement over Round 7
- they still were not strong enough on stock `crystal` query validation

Phase 2 result:

- switching from a proc-based compiled validator to a generated validator type
  produced the first clean validation win on both compilers

Files changed:

- `src/amber/validators/params.cr`
- `src/amber/controller/schema_integration.cr`
- `spec/amber/validations/params_spec.cr`
- `benchmarks/framework_performance_lab.cr`
- `benchmarks/framework_performance_profile.cr`

Key measured read from the focused profile harness:

- `crystal` query compiled vs validated: `1.1627x`
- `crystal` JSON-body compiled vs validated: `1.2689x`
- `acrystal` query compiled vs validated: `1.1042x`
- `acrystal` JSON-body compiled vs validated: `1.0803x`

Useful takeaway:

- the user instinct was right
- if the validation shape is known ahead of time, generating the checks
  directly is better than rebuilding or interpreting generic rule objects in
  the request path
- the next step is to expand this direct generated path carefully without
  falling back to a generic interpreter

### Round 9

- branch base: `experiment/framework-performance-validation-hybrid-round9`
- note: `benchmarks/FRAMEWORK_PERFORMANCE_ROUND9.md`

Kept direction:

- shared reusable validator contract for reusable definitions
- hybrid per-rule lowering inside `Params.compile`
- reusable fallback support for predicate blocks and other unsupported rules

What this round proved:

- the compiled validator API no longer has to reject mixed-rule validators just
  because one rule needs fallback behavior
- the simple direct compiled path still wins cleanly
- mixed-rule hybrid validators are promising, but not yet uniformly faster on
  every compiler/workload pair

Files changed:

- `src/amber/validators/params.cr`
- `src/amber/controller/schema_integration.cr`
- `spec/amber/validations/params_spec.cr`
- `spec/amber/controller/schema_integration_spec.cr`
- `benchmarks/framework_performance_lab.cr`
- `benchmarks/framework_performance_profile.cr`

Key measured read from the focused profile harness rerun:

- `crystal` simple query compiled vs validated: `1.1684x`
- `crystal` mixed query hybrid vs validated: `1.1608x`
- `crystal` simple JSON-body compiled vs validated: `1.2503x`
- `crystal` mixed JSON-body hybrid vs validated: `1.0483x`
- `acrystal` simple query compiled vs validated: `1.3127x`
- `acrystal` mixed query hybrid vs validated: `0.9535x`
- `acrystal` simple JSON-body compiled vs validated: `1.0625x`
- `acrystal` mixed JSON-body hybrid vs validated: `1.1998x`

Useful takeaway:

- preserving full framework capability inside the compiled validator API is
  feasible
- the right next move is to tighten the mixed fallback path and add compile
  diagnostics before calling this a fully promoted default fast path

### Round 10

- branch base: `experiment/framework-performance-validation-round10`
- note: `benchmarks/FRAMEWORK_PERFORMANCE_ROUND10.md`

Rejected for promotion:

- predicate-block specialization inside the hybrid compiled validator path
- metadata-only diagnostics were useful, but the runtime optimization itself is
  not settled enough to promote

What this round proved:

- the benchmark surface is better now because compiled validator shape is
  visible in the JSON output
- the direct-vs-fallback counts matched the intended lowering:
  - simple compiled validators: `3 direct / 0 fallback`
  - hybrid compiled validators: `2 direct / 1 fallback`
  - predicate-only validator: `0 direct / 1 fallback`
- the exact `acrystal` mixed-query hybrid weak spot from Round 9 moved in the
  right direction in the focused profile

Why it did not advance:

- the short framework lab was positive on both compilers
- the focused validation-only profile still showed regressions in several simple
  compiled paths
- until those two views agree, this is not a clean default-on win

Files changed:

- `src/amber/validators/params.cr`
- `spec/amber/validations/params_spec.cr`
- `benchmarks/framework_performance_lab.cr`
- `benchmarks/framework_performance_profile.cr`

Key measured read from the framework lab:

- `crystal` query compiled vs validated: `1.0616x`
- `crystal` query hybrid vs mixed: `1.0681x`
- `crystal` JSON-body compiled vs validated: `1.0962x`
- `crystal` JSON-body hybrid vs mixed: `1.0926x`
- `acrystal` query compiled vs validated: `1.0744x`
- `acrystal` query hybrid vs mixed: `1.1034x`
- `acrystal` JSON-body compiled vs validated: `1.1172x`
- `acrystal` JSON-body hybrid vs mixed: `1.0921x`

Key measured read from the focused profile:

- `crystal` simple query compiled vs validated: `0.9260x`
- `crystal` mixed query hybrid vs validated: `0.9279x`
- `crystal` predicate-only query compiled vs validated: `0.8706x`
- `crystal` simple JSON-body compiled vs validated: `1.0132x`
- `crystal` mixed JSON-body hybrid vs validated: `1.1294x`
- `acrystal` simple query compiled vs validated: `0.8553x`
- `acrystal` mixed query hybrid vs validated: `1.0764x`
- `acrystal` predicate-only query compiled vs validated: `0.9668x`
- `acrystal` simple JSON-body compiled vs validated: `0.9029x`
- `acrystal` mixed JSON-body hybrid vs validated: `0.9001x`

Useful takeaway:

- compile diagnostics were worth adding
- the next reliable improvement probably depends on either a different fallback
  seam or quieter hosted reruns, not on stacking more complexity onto this
  version of the specialization

## Recording Rule Going Forward

When a new round lands, append:

1. commit hash
2. short hypothesis summary
3. files changed
4. crystal same-session deltas
5. acrystal deltas if trustworthy, otherwise note them as provisional
6. whether an external hosted rerun has confirmed the change yet
