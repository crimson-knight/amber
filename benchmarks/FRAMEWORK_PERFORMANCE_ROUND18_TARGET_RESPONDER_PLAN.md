# Framework Performance Round 18 Target Responder Plan

Round 17 proved one useful thing: `respond_with` gets faster when it selects the
winning response branch before rendering or allocating response bodies. That is
only the first slice of the real architecture Amber needs.

Amber is a business application framework, not only an HTTP framework. The next
responder pass needs to support the same controller/business-action shape across
web, native desktop, mobile, and future targets without dragging unused response
systems into each compiled binary.

## Current State

The current implementation is still web-first:

- `src/amber/controller/helpers/responders.cr` maps response branches to HTTP
  content types: `html`, `xml`, `js`, `json`, and `text`.
- `src/amber/controller/helpers/render.cr` renders ECR templates for web views.
- `docs/guides/testing.md` already documents Amber patterns outside HTTP,
  including native macOS/menu bar apps, mobile companion apps, and AssetPipeline
  `test_id` usage.

So the framework intent is broader than the current responder implementation.
Round 18 should close that gap instead of continuing to shave tiny costs from
HTTP-only content negotiation.

## Architecture Target

The right shape is not just lazy evaluation. It is:

1. Compile a responder map from the controller DSL.
2. Prune branches that do not apply to the current compile target.
3. At runtime, select the winning branch within the remaining target-specific
   map.
4. Lazily evaluate only the selected branch body.

That gives us both properties we want:

- precompiled structure: the binary already knows which responder branches exist
- lazy execution: expensive view/render/build work happens only after selection

The same principle should apply outside `respond_with`. Amber should have a
precision profile where compile-time knowledge removes runtime generality:

- known compile target removes unrelated render/presentation systems
- known route table enables generated matchers for hot/static routes
- known maximum request concurrency enables bounded reusable request scratch
  slots
- known params schema enables fixed validation plans and lazy param
  materialization
- known response shape enables direct IO writes or reused builders instead of
  short-lived strings

The goal is not cleverness. The goal is to make hot paths boring enough that
LLVM can turn them into straight-line code with predictable branches and little
or no GC traffic.

## Compile Targets

Round 18 should introduce explicit compile-time target flags. Candidate flags:

- `amber_target_web`
- `amber_target_native`
- `amber_target_ios`
- `amber_target_android`
- `amber_target_cli`

Default behavior should remain web-compatible so existing apps keep compiling
without any new flags.

The important rule: if a branch is not for the active target, it should not need
to type-check, allocate, or link target-specific dependencies.

Example desired outcome:

```crystal
respond_with do
  web.html render("show.ecr")
  web.json UserSerializer.render(user)
  native.screen UserScreen.build(user)
  native.patch UserScreenPatch.from(user)
end
```

A web build should keep only the `web.*` branches. A native build should keep
only the `native.*` branches. Runtime selection should happen inside the kept
branch set.

## Compatibility Rule

Existing web syntax must continue working:

```crystal
respond_with do
  html render("show.ecr")
  json({id: user.id})
end
```

For compatibility, bare `html/json/text/xml/js` should be treated as web target
branches unless the framework later introduces a migration period with warnings.

## Public DSL Candidates

Two shapes are worth testing before committing:

```crystal
respond_with do
  web.html render("show.ecr")
  web.json UserSerializer.render(user)
  native.screen UserScreen.build(user)
end
```

```crystal
respond_with do
  html render("show.ecr"), target: :web
  json UserSerializer.render(user), target: :web
  screen UserScreen.build(user), target: :native
end
```

The first reads better and gives the macro clearer target namespaces. The second
may preserve more of the existing DSL shape. The benchmark/prototype should
choose based on compile-time pruning reliability, generated code clarity, and
backward compatibility.

## Proof Criteria

Do not promote this architecture until these pass on both stock `crystal` and
`acrystal`:

- Existing `respond_with` specs still pass.
- A web-target build can contain native-only responder branch code that would
  fail if type-checked, proving the native branch was pruned.
- A native-target build can contain web-only responder branch code that would
  fail if type-checked, proving the web branch was pruned.
- Cheap web responders remain neutral against the Round 17 runtime baseline.
- Expensive skipped branches remain faster than runtime branch construction.
- A target-pruned multi-branch responder shows less allocation/CPU cost than an
  equivalent runtime target switch.
- Precision candidates report both throughput and GC allocation deltas.
- Winning precision candidates get a source-level benchmark first, then an
  optional `--emit llvm-ir` or `--emit asm` inspection when the source benchmark
  shows a real win.

## Benchmark Shape

The benchmark needs three tiers:

- Web-only compatibility: current Round 17 scenarios stay in place.
- Target pruning proof: compile-only fixtures prove inactive target branches are
  not type-checked.
- Mixed application responder: one controller action declares web JSON, web HTML,
  native screen, and native patch branches, then builds/runs as separate target
  binaries.

The mixed responder benchmark should report:

- direct selected branch
- old runtime `respond_with_runtime`
- Round 17 web-only lazy macro
- Round 18 target-pruned lazy macro

That lets us answer whether the new architecture stacks on top of Round 17 or
only moves complexity around.

The precision benchmark lane should report:

- current Amber implementation
- precision/generated candidate
- selected branch without materializing params
- selected branch with lazy param materialization
- allocated bytes per iteration
- stock `crystal` and `acrystal` results

## Implementation Plan

1. Add an internal responder target model that can be driven by macro-generated
   branch metadata.
2. Teach the macro to recognize bare web branches and namespaced target branches.
3. Add compile-time pruning with `flag?(:amber_target_*)`.
4. Keep the current runtime responder as the safe fallback for unsupported DSL
   shapes.
5. Add compile-only specs that intentionally place invalid target-specific code
   behind pruned branches.
6. Add focused benchmarks for web-only, native-only, and mixed responder maps.
7. Promote only the smallest keeper that proves real avoided work without
   breaking standard Crystal compatibility.

## Non-Goals For This Pass

- Do not invent the whole native UI framework in the responder pass.
- Do not remove HTTP content negotiation.
- Do not force native dependencies into web builds.
- Do not require `acrystal`-only macro behavior.
- Do not disable or manually control the GC per request; prefer not allocating
  unused branch bodies in the first place.
- Do not reach for LLVM intrinsics before the Crystal source-level shape proves
  there is a real hot path. First make the code easy for LLVM to optimize.

## Current Verdict

Round 17 should be treated as a web responder optimization, not the final
responder architecture.

Round 18 should build the target-aware responder skeleton and prove compile-time
pruning. If that works, the later native view/render integration can plug into a
real responder map instead of being bolted onto HTTP content negotiation.

## First Proof Checkpoint

Added a standalone pruning proof:

- `benchmarks/respond_with_target_pruning_proof.cr`

The proof declares one web-only class and one native-only class, then puts both
branches in a single responder block. Each build defines only the class for the
active target. If the inactive branch leaked into generated code, the build
would fail during type-checking.

Verified commands:

- `crystal run benchmarks/respond_with_target_pruning_proof.cr`
- `crystal run -Damber_target_native benchmarks/respond_with_target_pruning_proof.cr`
- `acrystal run benchmarks/respond_with_target_pruning_proof.cr`
- `acrystal run -Damber_target_native benchmarks/respond_with_target_pruning_proof.cr`

Results:

- default/web target prints `web-html`
- native target prints `native-screen`

This confirms the core mechanism is compatible with stock Crystal and `acrystal`:
compile-time target pruning plus lazy selected branch execution is viable.

## Second Proof Checkpoint: Bounded Route Slot

Added a standalone precision-path probe:

- `benchmarks/precision_route_slot_probe.cr`
- `benchmarks/results/precision_route_slot_probe_round18.json`

The probe compares the current Amber route tree matcher with a deliberately
specialized route branch that scans the request path and writes param spans into
a reusable bounded slot. This models a future generated-router path for known
hot routes.

Verified with release builds on both compilers:

- `crystal build --release benchmarks/precision_route_slot_probe.cr`
- `acrystal build --release benchmarks/precision_route_slot_probe.cr`

Results with 1,000 routes and a dynamic route `/bench/users/:id/details`:

| Compiler | Scenario | IPS | Bytes/iteration | Ratio |
| --- | ---: | ---: | ---: | ---: |
| `crystal` | current Amber match | `4.44M` | `432` | `1.00x` |
| `crystal` | slot match, no param materialization | `59.24M` | `0` | `13.35x` |
| `crystal` | slot param size, no string materialization | `59.17M` | `0` | `13.75x` |
| `crystal` | slot param value, lazy string materialization | `51.31M` | `16` | `11.92x` |
| `acrystal` | current Amber match | `4.43M` | `432` | `1.00x` |
| `acrystal` | slot match, no param materialization | `59.17M` | `0` | `13.35x` |
| `acrystal` | slot param size, no string materialization | `58.96M` | `0` | `13.78x` |
| `acrystal` | slot param value, lazy string materialization | `51.11M` | `16` | `11.95x` |

This does not mean the production router gets a free 13x win. It means the
precision direction is real: the current matcher pays about 432 allocated bytes
per dynamic match in this probe, while a bounded slot can match and inspect a
param without allocating at all.

Actionable next step: prototype a generated precision route path behind an
opt-in compile flag, probably for explicitly marked hot routes first. The
compatibility path remains the existing router.
