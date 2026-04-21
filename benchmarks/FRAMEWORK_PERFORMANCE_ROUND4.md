# Framework Performance Round 4

Round 4 stacked two new focused passes on top of `4b8b1ac`:

- single-response `respond_with` fast paths
- specialized `String`/`Symbol` overloads for hot controller/router params access

## Verdict

Keep both changes.

The responder fast path finally improved the path it was supposed to improve:

- `amber_action_json_respond_with`
- `amber_dispatch_json`

And the specialized params overloads produced small but consistent wins across
query/body lookup and controller param access without breaking compatibility.

## Promoted Code Paths

- `src/amber/controller/helpers/responders.cr`
  - avoid allocating a response hash for the common single-response case
  - fast-path simple `Accept` headers without splitting
- `src/amber/controller/schema_integration.cr`
  - inline hot `params`/`raw_params` accessors
  - specialize schema-wrapper `[]`, `[]?`, and `has_key?`
- `src/amber/router/params.cr`
  - specialize `String` and `Symbol` overloads for hot lookup/write helpers
- `src/amber/validators/params.cr`
  - match the same specialized passthrough shape on the validator wrapper

## Crystal Result

Using the same-session control in
`benchmarks/results/framework_performance_lab_round3_control_crystal_r4.json`,
Round 4 improved the stacked branch on stock `crystal`:

- `amber_action_json_direct`: `291,522 -> 308,956` IPS (`+6.0%`)
- `amber_action_json_respond_with`: `266,836 -> 296,624` IPS (`+11.2%`)
- `amber_dispatch_json`: `248,100 -> 261,172` IPS (`+5.3%`)
- `amber_action_query_params`: `204,378 -> 217,151` IPS (`+6.2%`)
- `amber_dispatch_json_body`: `279,783 -> 295,652` IPS (`+5.7%`)

The six main framework-lab hotspots are now about `1.487x` mean and `1.446x`
geometric mean faster than the original framework baseline on `crystal`.

## ACrystal Result

`acrystal` still compiles the full framework lab and the targeted specs cleanly.

The short local Round 4 run also improved the exact paths this round changed
compared with the saved Round 3 rerun:

- `amber_action_json_direct`: `272,946 -> 309,553` IPS (`+13.4%`)
- `amber_action_json_respond_with`: `246,354 -> 301,632` IPS (`+22.4%`)
- `amber_dispatch_json`: `233,908 -> 262,738` IPS (`+12.3%`)
- `amber_action_query_params`: `212,605 -> 222,497` IPS (`+4.7%`)
- `amber_params_lookup_query`: `1,135,297 -> 1,213,784` IPS (`+6.9%`)

Because the local `acrystal` environment still has more run-to-run noise than
I want, treat the exact percentage as provisional. But compatibility is intact,
and the direction on the affected paths is good.

## Overall Read

At this point the gains are stacking cleanly:

- Round 1 and 2 removed a lot of params/controller overhead
- Round 3 improved dispatch bookkeeping
- Round 4 tightened negotiated JSON and hot param accessor paths

The remaining frontier is still request/response allocation pressure and GC in
the real write path, not route matching.

## Visual

Updated stacked comparison:

- `benchmarks/results/framework_performance_progress_round4.svg`
