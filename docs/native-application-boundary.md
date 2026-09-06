# Native application boundary

Status: development implementation, not a released Android support claim.

`require "amber/native"` exposes application-level contracts without loading
Amber's HTTP server. A hybrid app has separate web and native entrypoints over
shared Crystal domain rules, validation, use cases and state. Existing ECR/HTML
templates do not automatically become native Android Views.

## Available in this checkout

| Surface | Contract |
| --- | --- |
| `Amber::Schema::Definition` | Existing JSON value validation, typed results, coercion, custom and field validators |
| `Amber::Schema::FileMetadataValidator` | File metadata validation shared with the HTTP multipart parser; does not inspect real file contents or grant file access |
| `Amber::Native::Configuration` | Explicit application identity, environment and public JSON values; no Amber server YAML or environment mutation |
| `Amber::Native::ProcessManager` | Application-object start/foreground/background/stop hooks, not server jobs or OS process management |
| `Amber::Native::Lifecycle` | Ordered acquisition, reverse cleanup, duplicate notification handling, invalid/reentrant transition rejection and cleanup after failure |
| Platform-service interfaces | Async HTTP, key/value storage, secrets, app-private files and notifications; optional Android storage, HTTP, protected-secrets and app-private-file adapters, no pretend fallback implementations |

For schema values alone, use `require "amber/schema/value"`. The HTTP entrypoint
`amber/schema` additionally includes request parsing and controller integration.
`Amber::Schema::Parser::FileUploadValidator` remains a compatibility alias for
the extracted metadata validator.

`amber/native` intentionally excludes HTTP, OpenSSL, LibXML, YAML, routers,
controllers, mailers, jobs, websockets and server boot. An isolation fixture
checks the loaded constants at compile time, as well as exercising real schema,
configuration and lifecycle methods. The root Amber entrypoint and seven
server-facing entrypoints reject Android with an explanatory compiler error.
These guards are not a sandbox and do not prevent a consumer from explicitly
importing arbitrary Crystal standard-library or third-party server code.

## Application shape

```text
shared domain + validation + use cases + state
                 |
       +---------+----------+
       |                    |
web entrypoint        Android entrypoint
require amber         require amber/native
HTTP controllers      AssetPipeline UI::View screens
server adapters       Android platform adapters
```

`examples/hybrid_counter/shared.cr` owns a counter, name validation and state.
`web_controller.cr` exercises that same implementation from Amber HTTP actions.
`android.cr` renders it through native AssetPipeline controls. The Android
fixture imports AssetPipeline's public `ui/android/application` runtime directly;
it does not require showcase screen code. It currently reuses the development
Kotlin Activity shell and is not yet an independently generated Android project.

Keep deployment secrets, database credentials and privileged server operations
out of the APK. A native client calls an authenticated server API for remote
operations; it must not import server controllers or credentials into its
shared code. Native key/value storage is not Grant/database support.

## Host and ownership rules

- The host owns a logical application session and its `Lifecycle`. It serializes
  lifecycle hooks and service completions on one application thread. This class
  is not a cross-thread synchronization primitive.
- Register process managers through the constructor. `activate` starts a created
  session or resumes a backgrounded session; it never restarts managers. Start happens in order;
  background and stop happen in reverse order. Repeated foreground/background/
  stop notifications are harmless. Stopped and failed sessions cannot restart.
- Any transition failure stops all started managers, attempts every cleanup,
  preserves the original transition error and leaves the session failed.
- A service adapter returns an `Operation`. Cancellation is idempotent; each
  accepted request completes exactly once, including cancelled operations.
  Adapters must marshal results to the application thread and own their worker
  threads and foreign references. The interfaces do not provide that machinery.
- Android networking must use the platform TLS/trust implementation. Key/value
  storage, HTTP, protected secrets and app-private files now have explicit optional adapters; runtime permissions,
  notifications and user-selected documents need separately tested
  adapters. The core never substitutes insecure or pretend implementations.
- The example retains its store and lifecycle in process memory across Activity
  recreation and reopening the Activity in the same process. It intentionally
  does not persist data across process death. AssetPipeline's lifecycle callback
  now forwards the Android host's visibility events independently of rendering.

### Android host mapping

Register `UI::Android::Application.on_lifecycle` once in the Android entrypoint:
map `Foreground` to `Lifecycle#activate`, `Background` to `#background`, and
`Stop` to `#stop`. The lifecycle object and process managers live outside the
screen factory; rendering never starts a session.

The canonical Kotlin bridge requires the main looper for library loading, UI
callbacks, rendering, lifecycle events and debug reads. The host attaches one
surface, calls `foregroundHost` from `onStart`, `backgroundHost` from `onStop`,
and detaches/releases its View tree from `onDestroy`. Visibility here means
**started/visible**, not resumed/input-focused; permission prompts and multi-window
focus need more specific adapters when they matter. Configuration recreation
may produce a background/foreground pair, but it does not produce a second start.

`closeSession` is an explicit terminal operation after the surface is detached.
It is not called by `onDestroy`. A stopped/failed runtime session rejects new
surfaces; a fresh Android process creates a fresh session. Android does not
guarantee destruction callbacks when it kills a process, and `Application.onTerminate`
is not a production process-exit hook. Persist important state when it changes;
never depend on a final stop callback for durability. See Android's
[Activity lifecycle](https://developer.android.com/guide/components/activities/activity-lifecycle)
and [Application.onTerminate contract](https://developer.android.com/reference/android/app/Application#onTerminate()).

The single-surface bridge rejects a second owner instead of silently replacing
another Activity's tree. Full multi-Activity/multi-window ownership is not yet
supported. Lifecycle failures cross JNI as an error result, are logged, and make
the Kotlin session terminal; Crystal exceptions never unwind into the JVM.

## Validation

`require "amber/native/android_storage"` opts into the Android-backed
`Amber::Native::Android::Storage` implementation of the shared Storage interface.
The app must also install AssetPipeline and initialize its host services with the
application context before activation. This optional import does not add an
AssetPipeline or Android dependency to ordinary `amber/native` consumers.
See [Android storage](android-storage.md) for ownership, cancellation and limits.

`require "amber/native/android_secrets"` opts into a separate Android Keystore
adapter. It encrypts both identifiers and values, excludes the vault from backup
and never resets existing data after key loss or authentication failure.
See [Android protected secrets](android-secrets.md) for the security model,
bounded transport, cancellation semantics and explicit limitations.

`require "amber/native/android_files"` opts into bounded app-private binary
files. It does not grant access to external storage or user-selected documents.
See [Android files](android-files.md) for path rules, atomic-write semantics,
backup policy and cancellation/lifecycle behavior.

`require "amber/native/android_notifications"` opts into explicit local Android
notifications. Permission prompts are separate from posting and require an
application action and a resumed host; channel configuration is an explicit
native-manifest capability. See [Android notifications](android-notifications.md)
for lifecycle, queue ownership, user settings and bounded payload semantics.

The original hybrid-counter fixture remains intentionally in-memory. The CLI's
generated counter now persists a validated versioned snapshot and refuses to
overwrite an invalid stored snapshot. These are distinct fixtures and claims.

From this Amber repository with Crystal 1.21.0:

```bash
bash scripts/test_native_boundary.sh
```

This runs the native unit tests, a native-only host executable, a real ARM64
Android object build, eight negative server-import checks and the web/schema
regressions. It preserves compiler evidence under a temporary directory and
requires the expected guard message, not just any compilation failure.

With AssetPipeline's pinned Android dependencies, SDK and emulator available:

```bash
ASSET_PIPELINE_ROOT=/absolute/path/asset_pipeline \
CRYSTAL_CROSS_DEPS=/absolute/path/android-dependencies \
bash scripts/test_native_android_app.sh emulator-5554
```

The integration runner uses an isolated shard lookup containing only the
intended AssetPipeline checkout. It builds both native ABIs, the APK, test APK
and release bundle through the canonical host. It runs the shared Amber counter
test and captures a separate native-app
relaunch. It records actual source hashes from both dirty checkouts; the base
commits alone are not sufficient provenance for development builds. Run the
separate AssetPipeline `scripts/run_android_smoke.sh` lane for its showcase
renderer/density/lifecycle suite; that lane selects the showcase entrypoint.

## Remaining support gates

This boundary does not complete the Android target. Capability manifest v2,
the standalone CLI generator and lifecycle forwarding now have development
implementations and runtime tests. Android service adapters, safe target/metadata
regeneration, AgentC reference screens, full Tier A renderer/accessibility coverage,
physical-device and x86_64 runtime proof, CI and released-consumer proof remain
part of the larger AssetPipeline Android implementation plan.
