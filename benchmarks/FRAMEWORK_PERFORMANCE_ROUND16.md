# Framework Performance Round 16

Round 16 focused on `respond_with` because it sits on the framework's normal
rendering path for HTML views, JSON responses, and negotiated response formats.

## Verdict

Keep the new measurement harness.

Do not promote the production responder candidates from this pass. The local
A/B runs found a few promising individual numbers, but none of the candidates
improved the core paths cleanly enough to justify changing Amber's default
rendering behavior.

## Added Measurement Coverage

- single-format JSON `respond_with` with `Accept: application/json`
- single-format JSON `respond_with` with no `Accept`
- multi-format HTML default negotiation
- multi-format HTML `Accept` negotiation
- multi-format JSON `Accept` negotiation
- multi-format JSON wildcard negotiation
- multi-format `.json` extension negotiation
- schema-style NamedTuple `respond_with`

The focused runner is:

- `benchmarks/bin/framework_respond_with_truth_round.rb`

The expanded profile scenarios are in:

- `benchmarks/framework_performance_profile.cr`

## Baseline Ratios

Baseline file:

- `benchmarks/results/framework_respond_with_round16_baseline_crystal.json`

These ratios compare each `respond_with` path against its nearest direct
response or related responder path. A ratio below `1.0x` means the
`respond_with` path is slower than the comparison path.

| Scenario | Baseline median ratio |
| --- | ---: |
| single JSON `Accept` vs direct JSON | `0.7729x` |
| single JSON no `Accept` vs direct JSON | `0.8339x` |
| multi HTML default vs direct HTML | `0.8818x` |
| multi HTML `Accept` vs default negotiation | `0.9874x` |
| multi JSON `Accept` vs direct JSON | `0.7498x` |
| multi JSON wildcard vs JSON `Accept` | `0.9077x` |
| multi `.json` extension vs JSON `Accept` | `0.8299x` |
| schema NamedTuple `respond_with` vs direct JSON | `0.8153x` |

Plain-English read: there is real headroom in negotiated rendering, but the
safe fix is not as simple as shaving a branch or removing one tiny allocation.

## Rejected Candidates

Each candidate was measured by building the baseline commit and the candidate
worktree side by side, then alternating the same scenario through both binaries.
The numbers below are candidate iterations divided by baseline iterations.

| Candidate | Best-looking result | Why it was rejected |
| --- | ---: | --- |
| cached response keys + extension lookup | `.json` extension `1.1892x` | default HTML median fell to `0.9004x` |
| no-array multi-format lookup + extension lookup | single JSON `1.1692x` | default HTML median fell to `0.8679x` |
| extension lookup only | single JSON `1.1421x` | wildcard negotiation had `0/5` positive samples |
| common `Accept` fast path | wildcard negotiation `1.0529x` | single JSON and multi JSON medians regressed |
| fast selected-response storage | single JSON `1.0794x` | HTML `Accept` median fell to `0.8393x` |

Rejected result files:

- `benchmarks/results/framework_respond_with_round16_ab_crystal.json`
- `benchmarks/results/framework_respond_with_round16_ab2_crystal.json`
- `benchmarks/results/framework_respond_with_round16_ab_extension_crystal.json`
- `benchmarks/results/framework_respond_with_round16_ab_accept_fast_crystal.json`
- `benchmarks/results/framework_respond_with_round16_ab_fast_store_crystal.json`

## What This Tells Us

The important discovery is that the easy responder optimizations are not stable
enough. The next useful pass should not be another tiny branch-shaving pass.
It should measure and prototype a bigger responder design:

- preserve current `respond_with` behavior for compatibility
- add an opt-in lazy/compiled responder path for hot actions
- avoid evaluating non-selected formats, especially expensive HTML view renders
- keep complex `Accept` headers on the existing compatibility path
- measure full HTTP pressure with real templates, not just in-process response
  objects

The likely major win is not "make the current hash lookup a little cheaper."
The likely major win is "do not build or render response formats the request
will not use."
