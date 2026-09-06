# Native Android key/value storage

Development adapter, not a released support claim. This is ordinary app-private
state, **not secrets, Grant, general SQL access, or a Files API**.

An Android application installs Amber and AssetPipeline, initializes the canonical
Kotlin host with its application context, then explicitly imports:

```crystal
require "amber/native/android_storage"
storage : Amber::Native::Storage = Amber::Native::Android::Storage.new
storage.write("settings.theme", "dark") do |result|
  if result.is_a?(Amber::Native::ServiceError)
    # Report the typed error; do not claim the value was saved.
  else
    # The write completed. Update app state and invalidate a screen if needed.
  end
end
```

`read` completes with String, nil for a missing key, or ServiceError. Empty values
are distinct from missing keys. `write` and `delete` complete with nil or an error;
deleting a missing key succeeds. Requests are serialized on a JVM worker using
Android's [SQLiteOpenHelper](https://developer.android.com/reference/android/database/sqlite/SQLiteOpenHelper).
Values are bound as blobs, keys are bound parameters, and each mutation finishes
before reporting success. The store configures SQLite synchronous=FULL. Opening,
reading, writing, and closing the database do not run on the UI thread.

The public facade remains platform-neutral. This optional adapter connects its
Storage/Operation interfaces to AssetPipeline's service transport; Amber does not
duplicate Kotlin/JNI code. Networking, protected secrets, files, notifications
and permission flows still require their own adapters.

## Acceptance, cancellation and lifetime

- Keys must be nonempty valid UTF-8, at most 512 bytes. Values must be valid UTF-8,
  at most 1 MiB. Storage's byte-array JNI path preserves emoji and embedded NUL.
  Do not infer that the separate native View/text-input bridge has Unicode parity.
- The shared queue permits 64 accepted operations. Queue full, unavailable/closed
  transport or oversized input throws a typed ServiceError before returning an
  Operation; rejected requests do not also invoke a completion. Other accepted
  validation/IO errors complete asynchronously.
- Accepted requests complete exactly once on the host main looper. They do not
  invoke user callbacks inline before submission returns. Per-request resources
  are released as work completes; the shared worker/database are session-owned.
- `Operation#cancel` is idempotent. Cancellation delivers Cancelled after work
  finishes; it does not undo an already committed write. For an ambiguous outcome,
  read back the state or use application-level operation identifiers.
- Activity background/recreation does not cancel durable app operations. Explicit
  terminal session close cancels queued/in-flight replies and closes the worker
  store after accepted work. Process death cannot guarantee completion callbacks.
- No user data or storage keys are placed in normal service error messages/logs.
  Typed failures distinguish Unavailable, PermissionDenied, Cancelled,
  InvalidInput and IO.
- Updating application state is separate from rendering. Call
  `UI::Android::Application.invalidate` when an async result changes visible state.
  General reconciliation/focus preservation during whole-tree refresh remains
  unfinished renderer work.

## Versioned data and security

The generated app restores a complete versioned snapshot before exposing its
counter controls. It validates the version, keys, name and counter range before
mutating live state. It refuses to overwrite unreadable/invalid stored state.
The adapter installs an explicit corruption handler that fails instead of
deleting/recreating a damaged database. Tests compare the damaged file's bytes
before and after opening it. See Android's
[custom database error-handler API](https://developer.android.com/reference/android/database/DefaultDatabaseErrorHandler).
Successful saves are reported only after the storage completion, and an older
save completion cannot supersede a newer save's status. App-specific migration and
recovery UI remain the application's responsibility.

This store uses Android's application-private database directory. Backups follow
the app's explicit allowBackup policy; it is not encrypted secret storage. Never
put server credentials in it or treat the app sandbox as an authorization server.
Uninstalling/clearing app data removes this storage. Back up real user data before
running tests that mutate the application's own counter/name use case. The
canonical backend test uses and removes only its randomly named test database.

## Native contract fixture

```sh
AMBER_ANDROID_FIXTURE=storage \
ASSET_PIPELINE_ROOT=/absolute/path/asset_pipeline \
CRYSTAL_CROSS_DEPS=/absolute/path/verified-android-cache \
bash scripts/test_native_android_app.sh emulator-5554
```

`examples/native_storage/android.cr` checks real adapter/JNI round-trips,
deferred completion, GC rooting, invalid inputs, cancellation, queue saturation,
delete/missing semantics and callback cleanup. The shared Android platform test
also exercises database reopen, corrupt data and real SQLite failures. Generated
consumer tests independently save counter/name state, record the old process ID,
force a new process and require the stored values to be restored.
