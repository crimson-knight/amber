# We Found Another 34% in Amber's Request Path

**Publication status:** Public review draft 0.1

**Research date:** July 17, 2026

**Suggested audience:** Amber and Crystal developers, framework maintainers, and performance-minded application teams

![Amber request-path performance results](../../benchmarks/results/round22_framework_performance_overview.svg)

Performance work gets misleading quickly when the benchmark stops looking like an application.

A router can look impossibly fast if it only matches one static path in a tight loop. A serializer can look impossibly fast if no HTTP request reaches it. A framework can win a synthetic benchmark while giving back the entire advantage when an application reads an ID, parses a body, validates a field, and writes a response.

We wanted a number we could defend.

So we built a 1,000-route Amber application, gave it a realistic mix of static and dynamic routes, sent it GET, POST, PUT, PATCH, and DELETE traffic, exercised JSON and MessagePack bodies, and then ran the same deterministic workload locally and across two DigitalOcean machines.

The result was not one magic instruction or compiler flag. It was a much more useful answer: Amber's optimized router has moved the bottleneck, and the next large opportunity is how the framework turns request bodies into application data.

## The result in one table

On DigitalOcean's smallest Basic one-vCPU Droplet, with a separate four-vCPU load generator on the same private network, we measured:

| Whole HTTP request path | Median requests/second | Change |
| --- | ---: | ---: |
| current Amber JSON params | 21,795 | baseline |
| compile-time typed JSON prototype | 25,072 | **+15.0%** |
| MessagePack map prototype | 28,602 | **+31.2%** |
| MessagePack array prototype | 29,297 | **+34.4%** |

All three candidate body paths beat the current path in all seven paired trials. The complete remote matrix and its focused confirmation handled **23.76 million successful responses with zero socket errors and zero non-2xx responses**.

These are not isolated parser operations. Every request went through real TCP sockets, Crystal's HTTP parser, Amber's optimized router and pipeline, body decoding, field access, controller work, response serialization, and the Linux network stack.

## What "realistic" meant

The application installed 1,000 routes:

- 450 static routes
- 250 REST routes with an ID
- 150 ID-plus-action routes
- 50 nested-parameter routes
- 50 regex-constrained routes
- 50 glob routes

The repeated traffic table was 65% GET, 20% POST, 8% PUT, 5% PATCH, and 2% DELETE. Twenty percent of requests included query strings. Seventy percent selected a realistic hot set, but that locality was applied inside every method-and-route-shape group so less common route types still received traffic.

Writes carried an eight-field mobile or CRUD-style payload. Controllers consumed every field and generated an acknowledgement. Reads consumed captured route parameters and generated a response. The test did not earn throughput by parsing data that the application ignored.

That mix matters. In the local, socket-free control, typed JSON improved the read-heavy application by 42.0%, but improved the write-heavy application by 51.8%. MessagePack map improved them by 72.7% and 121.7% respectively. Body work becomes a larger part of the request as writes become more common.

## HTTP/1.1 is not the leaderboard blocker

One of our first questions was whether Amber is being held back by Crystal's HTTP/1.1 server.

For real applications, native HTTP/2 and HTTP/3 support would be valuable. HTTP/2 multiplexing and header compression can reduce connection pressure. HTTP/3 can behave better on lossy or high-latency networks. Amber applications can get those benefits today by terminating newer protocols at a reverse proxy.

But switching protocols would not automatically improve Amber's current TechEmpower or the-benchmarker score. TechEmpower's JSON workload is itself a cleartext HTTP/1.1 keep-alive test, and its plaintext workload is an HTTP/1.1 pipelining test. Crystal's standard server accepts HTTP/1.0 and HTTP/1.1. To move up that leaderboard, Amber first has to execute the HTTP/1.1 request path faster.

That is good news because the profile gives us concrete places to work.

## The old JSON path does too much

Amber's current general JSON path is flexible, but that flexibility has a cost. It reads the body into a string, parses a generic JSON tree, converts values into a string hash, and can parse nested values again when application code asks for typed data.

The typed JSON prototype takes advantage of information the framework already has at compile time. It buffers the bounded request body once and decodes directly into the known payload type. That simple change improved whole-request throughput by 15.0% on the hosted target while preserving JSON on the wire.

We also tested the seemingly more advanced answer: parse typed JSON directly from Crystal's `HTTP::FixedLengthContent` stream and avoid the body copy. It lost badly. Checked virtual `IO` reads cost more than one bounded copy for this payload. The fastest JSON result was not "zero copy at any cost." It was "one bounded buffer, one typed parse."

That failed experiment is worth publishing. It prevents us, and hopefully someone else, from optimizing toward an attractive theory that does not survive a complete request.

## MessagePack is promising, but it is not merged functionality

MessagePack produced the largest gain in this round. Its map payload was 222 bytes versus 257 bytes for JSON, and its compact array payload was 159 bytes. More importantly, typed decoding avoided the generic JSON tree and most of its temporary strings.

The public map representation is the practical choice because field names allow schemas to evolve. The array representation is faster and smaller, but positional fields should be reserved for explicitly versioned first-party clients.

This branch does **not** add a production MessagePack API to Amber. It adds pinned, reproducible prototypes and a deliberately specialized parser that measures the remaining ceiling. That parser does not implement every MessagePack type or the security limits required for untrusted input.

The ecosystem `msgpack-crystal` shard passed all 594 upstream examples under both Homebrew Crystal and our `acrystal` fork. It is a useful baseline, but its repository currently has conflicting license metadata and incomplete modern timestamp-extension support. Before Amber adopts it, the provenance needs to be clarified or the project needs an audited fork or implementation with body-size, nesting, collection, extension, numeric-overflow, malformed-input, and fuzz coverage.

MessagePack is a format specification, not an IETF RFC. Its registered media type is `application/vnd.msgpack`.

## The router work still matters

This experiment starts from the optimized byte-span router. The previous controlled round measured that matcher at 3.19 times the legacy matcher's throughput. Once HTTP parsing and the full Amber request path were included, the gain became 25.3%. On the smallest hosted target, the router alone produced an 11.0% whole-request gain.

Those numbers are not contradictory. `3.19x` means 219% faster matcher throughput. It becomes a smaller application gain because the router is only one part of a request.

The new CPU samples show optimized route selection at roughly 4% to 5% of self samples. It is still worth improving, especially for typed constraints and parameter readers, but it is no longer where most of Amber's unclaimed performance lives.

## What the CPU profile says to do next

Once MessagePack removes JSON token and string work, the largest visible areas are:

- virtualized kernel networking and soft IRQ handling;
- the optimized route selector;
- garbage-collected allocation;
- generic HTTP header parsing and hash lookup;
- socket reads and writes;
- response construction and buffering.

That gives us a practical next sequence:

1. Generate typed JSON validation and decoding from Amber schemas while keeping the current params API as the compatibility path.
2. Design an optional, audited MessagePack codec with map contracts by default and compact arrays only by explicit agreement.
3. Cache content-type parsing and specialize common header access.
4. Reuse bounded request and response scratch buffers without allowing references to escape the request.
5. Test borrowed-span HTTP parsing and reusable request objects in Crystal itself.
6. Coalesce response writes and compare a gather-write path such as `writev` with Crystal's buffered writer.

Disabling the garbage collector is not the safe shortcut it sounds like. Fibers can share threads, and request data can escape through logging, callbacks, or application state. Bounded buffers, immutable compile-time schemas, borrowed byte spans, and fewer heap objects attack the same cost without making memory lifetime unpredictable.

## Are we at Rust-level performance yet?

Not yet, and these DigitalOcean results should not be compared directly with a 40k or 50k leaderboard result from different hardware and a different workload.

What we do know is useful: on the exact same small target and realistic application, the best prototype moves Amber from 21.8k to 29.3k requests per second. Reaching 40k on that same machine would require another 36.5%. The profile suggests that the next jump will need lower-level HTTP representation and I/O work, not another collection of tiny controller tweaks.

That is an ambitious target. It is also now a measurable engineering program rather than a hope.

## Review the work

The complete branch is available for review:

- [Experiment branch](https://github.com/crimson-knight/amber/tree/experiment/framework-performance-protocol-codec-round22)
- [Standalone optimized router](https://github.com/crimson-knight/amber-router/tree/experiment/v2-byte-span-router)
- [Standalone router results and 55.7x explanation](https://github.com/crimson-knight/amber-router/blob/experiment/v2-byte-span-router/benchmarks/RESULTS.md)
- [Full technical report](https://github.com/crimson-knight/amber/blob/experiment/framework-performance-protocol-codec-round22/benchmarks/DIGITALOCEAN_FRAMEWORK_ROUND22.md)
- [Remote result matrix](https://github.com/crimson-knight/amber/blob/experiment/framework-performance-protocol-codec-round22/benchmarks/results/round22_digitalocean_framework_workload.json)
- [Compiler and object provenance](https://github.com/crimson-knight/amber/blob/experiment/framework-performance-protocol-codec-round22/benchmarks/results/round22_do_objects_manifest.json)

The branch contains a sequence of clear checkpoints, both compiler paths, raw benchmark results, Linux CPU profiles, workload generators, DigitalOcean lifecycle scripts, and a complete reproduction record. The temporary cloud resources were destroyed after the evidence was copied and independently verified.

We would especially value review of the workload assumptions, MessagePack safety requirements, typed-schema API direction, and the proposed Crystal HTTP internals work. Good performance claims get stronger when other people can challenge and reproduce them.

## References

- [Crystal 1.20.3 `HTTP::Server`](https://crystal-lang.org/api/1.20.3/HTTP/Server.html)
- [TechEmpower HTTP/1.1 JSON workload](https://github.com/TechEmpower/FrameworkBenchmarks/blob/R23/toolset/wrk/concurrency.sh)
- [TechEmpower pipelined plaintext workload](https://github.com/TechEmpower/FrameworkBenchmarks/blob/R23/toolset/wrk/pipeline.sh)
- [MessagePack format specification](https://github.com/msgpack/msgpack/blob/master/spec.md)
- [IANA MessagePack media type](https://www.iana.org/assignments/media-types/application/vnd.msgpack)
