# Amber Framework Performance Lab

This lab exists to push Amber V2 toward frontier-level framework performance
without losing sight of where the time actually goes.

The router lab already told us a lot about route matching. This suite answers a
different question:

> Relative to a raw Crystal HTTP baseline, which Amber framework layers are
> currently costing the most throughput and memory on request-heavy workloads?

## What It Measures

`benchmarks/framework_performance_lab.cr` benchmarks the hot request-path
components that show up in `plaintext` and `json` style workloads:

- raw Crystal plaintext response
- Amber controller plaintext response
- Amber full dispatch plaintext response
- extra no-op pipeline overhead
- raw Crystal JSON response
- Amber direct JSON response
- Amber `respond_with` JSON response
- Amber full dispatch JSON response
- raw query parsing
- Amber params lookup for query strings
- controller-level param access
- full dispatch with route + query params
- raw JSON body parsing
- Amber params lookup for JSON bodies
- Amber full dispatch for JSON-body requests

The suite writes JSON to `benchmarks/results/` and includes explicit comparison
pairs so we can rank the biggest framework gaps first.

## Running It

Quick smoke run:

```sh
bash benchmarks/bin/framework_perf_compare.sh --compiler crystal --warmup=1 --calc=1
```

Deeper run:

```sh
bash benchmarks/bin/framework_perf_compare.sh --compiler acrystal --warmup=2 --calc=5
```

Build-first flow:

```sh
bash benchmarks/bin/framework_perf_build.sh --compiler crystal --output /tmp/framework_perf_lab.crystal
AMBER_BENCH_COMPILER=/opt/homebrew/bin/crystal /tmp/framework_perf_lab.crystal --warmup=2 --calc=5
```

Rank the biggest gaps from the latest JSON:

```sh
ruby benchmarks/bin/framework_perf_rank.rb
```

## Auto-Research Loop

Use this loop for framework-wide performance work:

1. Run the framework lab on both `crystal` and `acrystal`.
2. Sort by lowest throughput ratio in `summary.comparisons`.
3. Pick the single worst Amber-vs-baseline gap that also matches a real
   benchmark shape we care about.
4. Profile only that scenario next.
5. Ship one focused hypothesis, not a grab bag.
6. Re-run this suite, then re-run the external HTTP benchmark that matches the
   same workload.
7. Keep the change only if both correctness and measured performance hold.

## Interpretation

- If `dispatch plaintext vs raw` is poor, the biggest wins are likely in
  routing, pipeline traversal, response finalization, or controller setup.
- If `respond_with JSON vs direct JSON` is poor, focus on content negotiation
  and responder allocation behavior.
- If `Amber params query lookup vs raw` or `Amber params JSON body lookup vs raw`
  is poor, focus on request parsing and parameter wrapper overhead.
- If `3 no-op pipes vs plain dispatch` is poor, middleware chaining is still too
  expensive.

## Next Extensions

The current suite focuses on request-path hot spots that matter for Amber's
TechEmpower-style `plaintext` and `json` cases. The next useful expansions are:

- ECR rendering and layout overhead
- exception/error-path throughput
- cookies/session overhead
- websocket handshake path
- DB-adjacent controller actions once the request path is tighter
