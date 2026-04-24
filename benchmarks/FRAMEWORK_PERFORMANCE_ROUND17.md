# Framework Performance Round 17

Round 17 tested a selective compiled/lazy `respond_with` path.

## Verdict

Keep the selective optimization candidate.

The first broad macro version was too aggressive: it made every block-style
`respond_with` use generated responder code, and that created noise/regressions
on cheap response bodies. The keeper version is narrower:

- single-format and cheap multi-format responses fall back to the existing
  runtime responder
- multi-format responses with call-shaped work, such as `html render(...)`, use
  generated code that evaluates only the selected response body
- no-block schema `respond_with(data)` delegates back to the schema helper

That gives us the optimization where it matters: avoid rendering or allocating
a response body that the current request will not use.

## Why This Is A Real Opportunity

This is not a branch-shaving optimization. It removes work from the request:

- old runtime shape: evaluate `html render(...)`, then evaluate `json(...)`,
  then select JSON and discard the rendered HTML
- selective compiled shape: select JSON first, then evaluate only the JSON body

That is the kind of optimization that can compound in a real app, especially on
mixed HTML/API controllers.

## Final Targeted Result

Final result file:

- `benchmarks/results/framework_respond_with_round17_selective_macro_vs_runtime_crystal.json`

These ratios compare the macro path against the old runtime responder in the
same binary.

| Scenario | Median ratio | Positive samples |
| --- | ---: | ---: |
| single JSON with `Accept` | `1.0177x` | `3/5` |
| single JSON without `Accept` | `0.8026x` | `2/5` |
| multi HTML default | `1.0094x` | `3/5` |
| multi HTML with `Accept` | `0.9502x` | `2/5` |
| multi JSON with `Accept` | `1.0371x` | `3/5` |
| heavy HTML branch skipped by JSON | `1.6735x` | `5/5` |
| heavy HTML branch selected | `1.0720x` | `4/5` |

Plain-English read:

- cheap cases are roughly neutral/noisy
- the intended avoided-work case is consistently faster
- when the expensive HTML branch is selected, the macro does not show a
  meaningful penalty locally

The single JSON no-`Accept` pair above is a noisy fallback-vs-fallback
comparison. A follow-up 9-sample spot check of that exact pair produced
`1.0067x` median with `5/9` positive samples, so I am not treating that line as
a confirmed regression. It should still be watched in the HTTP pressure pass.

## Rejected Shapes During This Round

These were measured and rejected before the selective gate:

- broad macro for every block-style `respond_with`
- macro-expanded schema/no-block `respond_with(data)`
- single-response generated path for cheap JSON-only responders

Why they were rejected:

- they improved some JSON ratios but introduced noise or regressions elsewhere
- schema/no-block response writing is not the same problem as negotiated
  rendering
- cheap single-format responders already have a good runtime fast path

Intermediate result files:

- `benchmarks/results/framework_respond_with_round17_lazy_macro_crystal.json`
- `benchmarks/results/framework_respond_with_round17_lazy_macro_crystal_long.json`
- `benchmarks/results/framework_respond_with_round17_lazy_macro_fast_single_crystal.json`
- `benchmarks/results/framework_respond_with_round17_macro_vs_runtime_crystal.json`

## Compatibility

- stock `crystal` responder/schema specs: pass
- `acrystal` responder/schema specs: pass
- stock `crystal` profile build: pass
- `acrystal` profile build: pass

## Optimization Rule Captured

The rule going forward should be:

- prefer avoided work over clever rewrites
- keep specialized existing paths when they are already cheap
- use compile-time generation when it removes allocations or skipped branch
  evaluation
- reject changes that only win in one micro-benchmark while hurting default
  HTML or JSON behavior

This is probably not the final optimization in the stack. It is a good one
because it targets a full category of wasted work, but the next frontier is
still full HTTP pressure with real view templates and response finalization.
