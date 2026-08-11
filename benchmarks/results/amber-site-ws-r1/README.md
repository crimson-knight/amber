# Amber website HTTP and WebSocket evidence

Measured August 11, 2026 against the Amber Framework website release candidate
over a private DigitalOcean VPC.

- Target: `s-1vcpu-512mb-10gb`, one shared vCPU, 512 MB advertised memory
- Load generator: `c-4`, four dedicated vCPUs
- Server: Amber `2.0.0-beta.2`, Crystal 1.21.0, Linux `x86_64-v2`
- Source base: `2bcae249e912f84ecab1d849393c48fed6b729ef`
- Source patch SHA-256: `89b970a09f028f990c2d585d4835917b9a6e7748f9b4cdf47a790610f92017de`
- Deployed executable SHA-256: `984b11cbfc178d166fca428c0cb5ac56036f84e9ab675f774cb30592a61050ff`

The `http` directory contains five 15-second `wrk` trials per path after a
five-second warmup. The `ws` directory contains connection-holder output and
three 10-second HTTP trials performed during each connection hold. All HTTP
runs used four threads and 16 persistent connections.

The complete normalized result, resource snapshots, totals, method, and limits
are published by the site as
`/benchmarks/amber-v2-site-websocket-2026-08-11.json`.

Important boundary: the WebSocket clients joined `site:proof` and then stayed
idle. The sequential stages were noisy—the 500-client HTTP result was lower
than the 1,000-client result—so they are evidence of the tested boundary, not a
causal scaling curve or production capacity promise.
