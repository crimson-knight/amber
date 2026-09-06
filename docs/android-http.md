# Android HTTP client

`require "amber/native/android_http"` provides
`Amber::Native::Android::HTTPClient`, implementing the existing native HTTPClient
and Operation contracts. The optional adapter requires AssetPipeline's Android
application runtime. Ordinary `amber/native` remains free of Android, AssetPipeline,
Crystal HTTP/OpenSSL and server boot dependencies.

```crystal
require "amber/native/android_http"

client : Amber::Native::HTTPClient = Amber::Native::Android::HTTPClient.new
operation = client.request(Amber::Native::HTTPRequest.new("GET", "https://example.com/api")) do |result|
  case result
  when Amber::Native::HTTPResponse
    # Check result.status, then interpret result.body for this application.
    # HTTP 4xx/5xx are responses, not transport failures.
  when Amber::Native::ServiceError
    # Decide whether to show an error, retry, or remain offline.
  end
end
# operation.cancel is idempotent; cancellation still completes asynchronously.
```

The host must initialize `CrystalBridge` with the application context and declare
`android.permission.INTERNET` (the capability manifest's explicit network opt-in).
Missing permission is an asynchronous `PermissionDenied` result. All submissions,
cancellations and completions belong to the application/main-looper thread.
Networking runs on four separate JVM workers, independently of serial storage.
The Crystal service registry limits combined accepted services to 64 operations.
OkHttp's own manifest requests INTERNET. Generated applications and the offline
showcase explicitly remove that transitive declaration unless app metadata opts
in. Package inspection checks the actual merged APK permission, not only the
source manifest. The controlled TLS debug manifest explicitly opts back in.

## Security and behavior

- AssetPipeline uses a pinned Android OkHttp artifact with platform TLS trust and
  hostname verification. No custom production trust manager, hostname bypass,
  Crystal OpenSSL, logging interceptor or bundled CA is installed.
- Android's network-security policy controls cleartext HTTP. The default target
  disallows it; applications must explicitly opt in to appropriate domains if
  needed. A debug-only test CA is not a cleartext opt-in.
- Redirects are returned as 3xx responses. No automatic cross-host credential
  forwarding or HTTPS downgrade occurs. Retries, cookies and disk caching are
  not enabled by this adapter; applications own those policies.
- GET, HEAD, POST, PUT, PATCH, DELETE and OPTIONS are supported. GET/HEAD bodies
  are rejected; absent POST/PUT/PATCH bodies become empty bodies. Request URLs
  must be ASCII HTTP(S), with percent-encoding where needed, and must not contain
  userinfo credentials or fragments. Headers use ASCII token names and values
  without control-character injection. Case-duplicate and transport-owned headers
  (including Host, Content-Length, Connection and Transfer-Encoding) are rejected.
- Body bytes preserve NUL, non-UTF-8 binary and Unicode exactly. Response header
  names are lowercased and duplicate values are retained in order. Transparent
  gzip decoding is the HTTP client's default; limits apply to decompressed data.
- Errors are typed and sanitized: `InvalidInput`, `PermissionDenied`, `Cancelled`,
  `Network`, `IO`, or `Unavailable`. TLS, connection, timeout and response-limit
  failures return Network, without URLs, credentials, bodies or native exception
  messages. Valid HTTP error responses retain their status/headers/body.

## Bounds, cancellation and ownership

The binary service wire is version 1, big-endian signed Int32 lengths and fields:
request version, timeout, method, URL, header count/pairs, body length and body;
response version, status, header count/pairs, body length and body. Metadata is
strict UTF-8; payloads never pass through JNI modified UTF-8 or base64.

Requests and responses have a 1 MiB transport envelope, at most 900 KiB bodies,
128 header pairs, 32 KiB headers, 8 KiB request URL and 16-byte method. Incoming
bodies are bounded while reading, including unknown-length/chunked bodies. This
is an in-memory API client, not streaming downloads, uploads or WebSockets.

`timeout_ms` is 1..120000, default 30000. The client applies a whole-call timeout
once network execution begins, plus 30-second connect/read/write limits. Time in
the bounded worker queue and first-use client initialization is outside that
call timeout. The system DNS resolver can delay worker cleanup; this is not a
hard real-time completion deadline for every Android system condition.

Cancellation marks the accepted operation and cancels an active HTTP call. The
result is delivered only after its response stream/call cleanup has run; pending
records are removed before invoking the Crystal callback. A late cancellation
before host delivery wins over a response. It does not undo a server-side effect
or prove that the server did not receive a cancelled request. Rejected submissions
throw before returning an Operation and do not also call the completion.

No Activity is retained for networking. Responses are closed on workers, byte
arrays are copied through bounded JNI frames, and Crystal callbacks run only on
the main looper with checked GC entry. No idle HTTP connections are retained.
Terminal session close cancels accepted network operations and shuts down their
executor; replies still drain on the main looper. Process death can preempt cleanup.

Update state in the completion and call `UI::Android::Application.invalidate`
when visible content should refresh. Full-tree refresh/IME reconciliation limits
of the existing host still apply; networking does not silently replace the UI.

## Verification and dependency policy

`scripts/test_native_android_http.sh <serial> [evidence]` creates ephemeral test
certificates and loopback servers. Only its explicitly opted-in debug source set
trusts that CA. The test covers a trusted certificate, a trusted-but-wrong-host
certificate, an untrusted certificate, denied cleartext, binary POST/PATCH,
repeated headers, HTTP errors, explicit redirects, body limits, timeout, GC/deferred
callbacks, storage progress during four network calls, native-button cancellation,
recreation and zero pending/native references. Server receipt checks reject policy
leaks, and the release bundle must exclude the test CA/configuration.

The test server's host ports are dynamic. Four reserved device reverse ports
(18443..18446) must be free; existing mappings are never overwritten. Cleanup
removes only the mappings it created and stops its servers. No system/user trust
store or global TLS verifier is changed. Temporary fixture keys are test-only,
expire after two days, and must not be included in public evidence uploads.
`AMBER_ANDROID_FIXTURE=http-denied scripts/test_native_android_app.sh <serial>`
tests the inverse: the installed target has no INTERNET permission and a real
Amber/JNI request completes with PermissionDenied and no pending operation.

Runtime dependencies are shared by the showcase and generated apps through
AssetPipeline's `android/runtime/dependencies.gradle.kts`. OkHttp 5.3.2 is pinned
for the SDK 35 host; Kotlin is 2.2.21. OkHttp 5.5.0 was rejected by the real AAR
compatibility check because it requires compileSdk 37. Do not suppress that check;
upgrade dependencies together with the Android toolchain and repeat these tests.
Gradle dependency locking/checksum provenance and current store-target policy
remain release gates, not claims established by these local runtime tests.

Primary references: [Android network-security configuration](https://developer.android.com/privacy-and-security/security-config),
[OkHttp request/cancellation recipes](https://lysine.dev/okhttp/recipes/), and
[OkHttp release history](https://lysine.dev/okhttp/changelogs/changelog/).
Manifest overrides follow [Android's manifest-merger rules](https://developer.android.com/build/manage-manifests).
