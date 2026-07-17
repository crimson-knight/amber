# Amber protocol and body-codec experiment, round 22

![Amber framework request-path performance](results/round22_framework_performance_overview.svg)

## Bottom line

HTTP/1.1 is not the reason Amber is below the fastest TechEmpower or the-benchmarker entries. Those published tests are themselves HTTP/1.1 tests. TechEmpower's JSON test uses cleartext HTTP/1.1 keep-alive without pipelining; its plaintext test adds 16-request pipelining. The-benchmarker currently drives HTTP/1.1 and disables keep-alive. Amber must first get faster on HTTP/1.1 to move up either leaderboard.

HTTP/2 and HTTP/3 still matter for real products. Multiplexing, HPACK/QPACK, and QUIC can improve behavior on high-latency or lossy networks, but they do not remove controller, routing, body-decoding, allocation, serialization, or kernel work. Crystal 1.20.3's standard `HTTP::Server` accepts HTTP/1.0 and HTTP/1.1; it does not contain an HTTP/2 framing/HPACK server or an HTTP/3/QUIC server. Proxy termination is the low-risk way to give Amber applications HTTP/2 and HTTP/3 today while a native transport is developed separately.

The largest confirmed framework opportunity in this round is Amber's request-body path:

| Remote 1-vCPU result | Median RPS | Change from current Amber JSON | p50 | p99 | Paired wins |
| --- | ---: | ---: | ---: | ---: | ---: |
| current Amber JSON params | 21,795 | baseline | 655 us | 4.20 ms | - |
| buffered typed JSON | 25,072 | **+15.0%** | 559 us | 3.31 ms | 7/7 |
| streaming MessagePack map | 28,602 | **+31.2%** | 513 us | 3.14 ms | 7/7 |
| buffered MessagePack array | 29,297 | **+34.4%** | 498 us | 3.12 ms | 7/7 |

These are whole HTTP requests over real sockets on DigitalOcean's smallest Basic Droplet, not codec operations in isolation. The load generator received **18,728,053 successful responses with zero socket errors and zero non-2xx responses** in the seven-variant matrix.

The default header and request-method cleanups are safe but not a meaningful hosted throughput claim. A separate 11-pair confirmation processed another **5,033,193 successful requests** and measured a paired median of **+0.8% RPS** and **+0.5% requests per CPU-second**. Those changes remove unnecessary policy headers and ordinary-POST allocation while preserving behavior; the body decoder is where the large gain is.

## The application we simulated

The fixture is deliberately a mature, mixed application rather than a static-route best case. It installs 1,000 routes and replays the same deterministic 4,096-request table for every codec and compiler binary.

| Installed route shape | Count | Sampled requests | Example work |
| --- | ---: | ---: | --- |
| static | 450 | 1,844 (45%) | literal endpoint lookup |
| REST ID | 250 | 1,024 (25%) | trailing integer-like, UUID, ULID, or slug parameter |
| ID plus action | 150 | 613 (15%) | captured ID followed by a literal action |
| nested params | 50 | 205 (5%) | two captured identifiers |
| constrained | 50 | 205 (5%) | integer, UUID, or ULID regex constraint |
| glob | 50 | 205 (5%) | captured multi-segment tail |

The installed route table is 400 GET, 300 POST, 153 PUT, 100 PATCH, and 47 DELETE routes. The read-heavy remote traffic mix is 2,665 GET (65%), 820 POST (20%), 328 PUT (8%), 203 PATCH (5%), and 80 DELETE (2%). Seventy percent of requests select the first 20% within each method-and-shape cell to model real hot endpoints without starving any route class. Twenty percent include query strings.

Writes carry an eight-field mobile/CRUD payload containing strings, an integer, a float, a boolean, and string tags. Controllers consume every decoded field and serialize an acknowledgement; reads consume captured route parameters and serialize a response. Wire sizes are 257 bytes for JSON, 222 bytes for MessagePack map (-13.6%), and 159 bytes for MessagePack array (-38.1%).

The workload includes Crystal's HTTP parser and serializer, Amber routing and pipeline dispatch, body decoding, field use, controller response work, and JSON response serialization. The local CPU lane excludes only sockets and kernel scheduling. The hosted lane adds a fresh server process for every trial, private-VPC TCP, Linux scheduling, and a separate load generator.

## What the local controls say

Body work becomes a larger share as the application performs more writes. That is why the local gains grow from the read-heavy profile to the write-heavy profile.

| Traffic profile | Current JSON | Typed JSON | MessagePack map | MessagePack array |
| --- | ---: | ---: | ---: | ---: |
| read-heavy, 20% POST | 309,480/s | 439,461/s (**+42.0%**) | 534,501/s (**+72.7%**) | 575,985/s (**+86.1%**) |
| balanced, 30% POST | 245,763/s | 356,068/s (**+44.9%**) | 476,314/s (**+93.8%**) | 498,707/s (**+102.9%**) |
| write-heavy, 40% POST | 196,974/s | 299,043/s (**+51.8%**) | 436,687/s (**+121.7%**) | 448,288/s (**+127.6%**) |

| Allocation per request | Current JSON | Typed JSON | MessagePack map | MessagePack array |
| --- | ---: | ---: | ---: | ---: |
| read-heavy | 4,776 B | 3,392 B (-29.0%) | 2,569 B (-46.2%) | 2,664 B (-44.2%) |
| balanced | 6,650 B | 4,377 B (-34.2%) | 3,003 B (-54.8%) | 3,162 B (-52.5%) |
| write-heavy | 8,354 B | 5,272 B (-36.9%) | 3,399 B (-59.3%) | 3,615 B (-56.7%) |

Amber's existing JSON path reads the body into a string, builds a generic `JSON::Any` tree, converts values into `Hash(String, String)`, and reparses nested JSON when typed values are requested. The typed JSON prototype buffers once and decodes directly into the compile-time-known payload type. It keeps JSON compatibility while removing the generic tree and string round trip.

Parsing typed JSON directly from `HTTP::FixedLengthContent` looked like the obvious zero-copy win, but it was slower: 250,203/s in the read-heavy lane versus 309,480/s for current Amber and 439,461/s for buffered typed JSON. Crystal's checked, virtual `IO` reads cost more here than one bounded body copy. The keeper is "one bounded buffer, one typed parse," not streaming one byte at a time.

The isolated codec benchmark explains the upper bound. Current Amber JSON params decode at 378,644 payloads/s and allocate 5,328 B/op. MessagePack map reaches 2.51M/s with 928 B/op; array reaches 3.93M/s with 672 B/op. A hand-written typed map-subset parser reaches 3.78M/s with 496 B/op. That specialized parser is useful proof that generated field dispatch has headroom, but it is intentionally not a general or production MessagePack implementation.

## What the CPU samples expose

Linux `perf` captured 14,501 legacy-JSON samples and 14,207 MessagePack-map samples with zero lost samples while the separate load generator sustained 23.3k and 27.2k RPS respectively.

| Hot area | Current JSON sample | MessagePack map sample | What it says |
| --- | ---: | ---: | --- |
| virtual NIC transmit (`iowrite16`) | 6.74% | 7.76% | faster application code exposes kernel/network cost |
| soft IRQ handling | 3.90% | 4.58% | the single vCPU is doing meaningful packet work |
| optimized route selection | 3.72% | 4.92% | routing is no longer dominant, but still worth a targeted pass |
| `GC_malloc_kind` | 3.31% | 2.80% | fewer allocations help; GC is still visible |
| secondary libgc allocation path | 2.47% | 1.70% | MessagePack reduces allocator pressure |
| JSON string/token lexing | at least 1.13% self | absent | typed/binary decoding removes this work |
| header hash lookup and parsing | at least 2.9% self | at least 2.5% self | HTTP header representation is a credible next target |

These percentages are self-sample shares, not additive end-to-end timings. A function can also appear below another sampled stack. They are best used to choose the next controlled experiment, not to promise that deleting one symbol produces the same percentage gain.

The next high-confidence experiments are therefore:

1. Generate typed JSON validation/decoding from Amber schemas at compile time and expose it as an opt-in fast path while preserving today's `params` behavior.
2. Cache parsed content type and specialize common header access so ordinary requests do not repeatedly build and search a fully generic header representation.
3. Reuse bounded body and response scratch buffers per execution context, with strict maximum sizes and no object references escaping the request.
4. Coalesce response headers and body into fewer writes, then test `writev` or an equivalent gather-write path against Crystal's buffered writer.
5. Prototype borrowed-span HTTP request parsing and a reusable request object in a Crystal fork, because this now has more upside than another broad router rewrite.
6. Continue the router work narrowly: typed integer/UUID/ULID constraint scanners, typed param readers, and generated literal-child dispatch must beat the existing span trie in a full-request test.

Disabling the garbage collector for a request is not a safe shortcut. Crystal fibers can share a thread, request objects can escape through logging or callbacks, and Boehm GC does not provide a cheap per-request generation that Amber can reset safely. Bounded scratch buffers, immutable compile-time schemas, borrowed spans, and fewer heap objects attack the same cost without creating memory-lifetime bugs.

## MessagePack decision

MessagePack is worth pursuing as an optional Amber codec. Its registered media type is `application/vnd.msgpack`. The map representation should be the public default because named fields can evolve; the array representation should be an explicit compact contract for first-party clients that agree on field order. JSON should remain the compatibility default, and content negotiation should make format choice explicit.

The benchmark uses `crystal-community/msgpack-crystal` 1.3.5 as the ecosystem baseline and ran its unchanged upstream suite on both compilers: 594 examples, zero failures on each. It is fast, but Amber should not take a production dependency yet. The package metadata says MIT while the README says Apache 2.0 and the repository has no root license file. It also lacks modern MessagePack timestamp-extension support. Those provenance and format gaps need resolution, or Amber needs an audited implementation/fork with:

- body-size, string-size, collection-size, nesting-depth, and extension-size limits;
- duplicate-key, unknown-field, numeric-overflow, invalid-UTF-8, and truncated-input behavior;
- the complete MessagePack format and timestamp extension rather than the benchmark's typed subset;
- cross-codec equivalence, malformed-input, fuzz, and denial-of-service coverage.

The hand-written subset should not be shipped. It answered the research question: generated field dispatch can nearly match array decoding while retaining map field names, so a safe macro-generated decoder is a promising implementation direction.

## Compiler and behavior compatibility

| Gate | Homebrew Crystal 1.20.3 | `acrystal` 1.20.0-dev `[6636853e8]` |
| --- | ---: | ---: |
| complete Amber suite | 2,338 examples, 0 failures | 2,338 examples, 0 failures |
| router legacy flags | 285 examples, 0 failures | 285 examples, 0 failures |
| targeted request/context behavior | 58 examples, 0 failures | 58 examples, 0 failures |
| upstream MessagePack suite | 594 examples, 0 failures | 594 examples, 0 failures |

Both compilers produce correct versions of every workload and pass cross-decoder field equality checks. On the hosted matrix, `acrystal` JSON reached 24,445/s versus stock optimized JSON at 21,607/s, while its MessagePack map reached 28,410/s versus stock at 28,602/s. That is not a consistent compiler-wide multiplier. The important result is that the same source and benchmark flow work on both compilers.

## Reproduction and evidence

The hosted target was a Basic `s-1vcpu-512mb-10gb` Droplet with 480 MB visible RAM. A separate CPU-Optimized `c-4` Droplet generated load over a dedicated `10.141.0.0/20` private VPC. All seven Linux binaries were cross-compiled as release-mode `x86_64-v2` objects, linked on the target, hashed, and then run with 16 connections, four `wrk` threads, five seconds of warmup, 15 seconds of measurement, and seven rotating repetitions. The deterministic request-table SHA-256 is `8543042f1684cf2a42ca7759a4166c171af6aaf22678aa88dee7eab407cbe0f5`.

The lab existed from 2026-07-17 12:33 UTC until teardown at approximately 13:20 UTC. At listed rates, about 47 minutes of the $0.00595/hour target and $0.125/hour load generator cost approximately **$0.10** before account-specific billing. Both Droplets and the dedicated VPC were destroyed. A fresh query in the `agentc` context returned no `amber-benchmark` Droplets and only the unrelated pre-existing `default-nyc3` and `default-nyc1` VPCs.

Evidence files:

- [`round22_digitalocean_framework_workload.json`](results/round22_digitalocean_framework_workload.json): 49-trial hosted codec/compiler matrix.
- [`round22_digitalocean_default_cleanup_confirm.json`](results/round22_digitalocean_default_cleanup_confirm.json): focused 22-trial default-path confirmation.
- [`round22_codec_stock.json`](results/round22_codec_stock.json) and [`round22_codec_acrystal.json`](results/round22_codec_acrystal.json): codec ceilings, allocation, and wire sizes.
- [`round22_workload_read_heavy_legacy_stock.json`](results/round22_workload_read_heavy_legacy_stock.json), [`round22_workload_balanced_legacy_stock.json`](results/round22_workload_balanced_legacy_stock.json), and [`round22_workload_write_heavy_legacy_stock.json`](results/round22_workload_write_heavy_legacy_stock.json): current-path controls; sibling files contain every candidate.
- [`round22_stock_json_legacy_perf.txt`](results/round22_stock_json_legacy_perf.txt) and [`round22_stock_msgpack_map_perf.txt`](results/round22_stock_msgpack_map_perf.txt): flat Linux CPU profiles.
- [`round22_do_objects_manifest.json`](results/round22_do_objects_manifest.json): source commit, compiler versions, target CPU, object hashes, and exact link commands.
- [`round22_do_binaries_manifest.json`](results/round22_do_binaries_manifest.json): deployed hashes, sizes, and compiler provenance.

Protocol and format references:

- Crystal [`HTTP::Server`](https://crystal-lang.org/api/1.20.3/HTTP/Server.html) and its [HTTP version parser](https://github.com/crystal-lang/crystal/blob/1.20.3/src/http/common.cr#L21).
- TechEmpower R23 [`wrk` JSON test](https://github.com/TechEmpower/FrameworkBenchmarks/blob/R23/toolset/wrk/concurrency.sh) and [pipelined plaintext test](https://github.com/TechEmpower/FrameworkBenchmarks/blob/R23/toolset/wrk/pipeline.sh).
- [HTTP/2, RFC 9113](https://www.rfc-editor.org/rfc/rfc9113.html) and [HTTP/3, RFC 9114](https://www.rfc-editor.org/rfc/rfc9114.html).
- [MessagePack format specification](https://github.com/msgpack/msgpack/blob/master/spec.md) and [IANA media type registration](https://www.iana.org/assignments/media-types/application/vnd.msgpack).
