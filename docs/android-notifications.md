# Android local notifications — development adapter

`amber/native/android_notifications` implements the shared Notifications interface
using AssetPipeline's canonical Android host. This is immediate, local posting:
not push messaging, scheduling, background execution, foreground services, custom
actions, or a release-support claim. Plain `amber/native` stays platform-neutral.

```crystal
require "amber/native/android_notifications"

notifications = Amber::Native::Android::Notifications.new
# Call from an explicit application action, after explaining why it is useful.
notifications.request_permission do |result|
  if result == true
    notifications.post(Amber::Native::Notification.new(
      42, "updates", "Export complete", "Your document is ready."
    )) { |posted| # nil means accepted by Android; handle ServiceError explicitly.
    }
  end
end
```

## Explicit app configuration

The CLI's v2 native manifest accepts:

```yaml
android:
  application_id: dev.example.app
  capabilities:
    notifications: true
  notification_channels:
    - id: updates
      name: Updates
      description: Export and task completion
      importance: low
```

Notification capability requires target SDK 33 or newer, so Android cannot
substitute legacy automatic prompt timing. The default target remains 35.
Generation emits POST_NOTIFICATIONS, a small white drawable icon, localized
channel string resources, and an XML channel catalog referenced by application
metadata `dev.assetpipeline.notification_channels`. A handwritten host must
provide this same declaration and catalog. Merely adding a permission without
the catalog does not enable this adapter. Offline/default generated apps remove
library-supplied POST_NOTIFICATIONS from the merged manifest. Generation currently
refuses to overwrite existing files; unified metadata regeneration remains open.

The catalog permits at most 32 unique channel IDs, with ASCII letters/digits and
`_.-`, starting with a letter/digit, at most 128 bytes. Channel display names are
nonblank and at most 128 UTF-8 bytes; descriptions at most 1,024 bytes. Importance
is `low`, `default`, or `high`; low is the default. New channels are silent, with
vibration and badges disabled. An existing channel's settings are never reset by
this adapter, so user-selected sound, importance and blocking remain authoritative.
Unknown channels fail InvalidInput rather than creating unbounded channels.
These policies follow Android's [channel model](https://developer.android.com/develop/ui/compose/notifications/channels).

## Permission and lifecycle contract

- No initialization, render, channel declaration, post, or cancellation prompts
  for permission automatically. Only `request_permission` may open the OS dialog.
- On API 33+, a needed prompt requires an attached, resumed ComponentActivity.
  Call `CrystalBridge.attachHost(this)` during onCreate, before STARTED, and
  detach during onDestroy. Both canonical hosts do this.
- Already-enabled permission returns true without a dialog. A denial or dismissal
  returns the actual current app-wide state, usually false; absent opt-in reports
  PermissionDenied. A needed prompt without a resumed host reports Unavailable.
  API 31–32 queries app-wide notification settings without a runtime dialog.
- Lifecycle-owned ActivityResultRegistry registration reconnects an outstanding
  flight across configuration recreation. A non-configuration host finish
  abandons outstanding requests with Unavailable; stale results cannot complete
  a later host's request. Process death loses application callbacks; they are
  not persisted or replayed as successful operations after restart.
- Concurrent permission callers share one OS dialog. Cancellation completes that
  caller with Cancelled, but cannot dismiss the OS dialog or undo an app-wide
  grant. A later caller may join the still-open dialog. No worker blocks on it.

Android documents the [notification permission rules](https://developer.android.com/develop/ui/compose/notifications/notification-permission)
and [lifecycle-owned result registration](https://developer.android.com/training/basics/intents/result).
This adapter does not open Settings or retry prompts without another explicit
application request. Applications should explain denied/unavailable states to
the user and avoid repeated permission nagging.

## Posting, ownership and limits

Notification IDs are nonnegative Int32 values. Title is nonblank and at most
1,024 UTF-8 bytes; body may be empty and is also at most 1,024 bytes. Text must be
strict UTF-8 without NUL. These byte limits fit within Android's string bound;
the adapter rejects oversized text rather than letting the platform silently
truncate it. See the [platform truncation rule](https://android.googlesource.com/platform/frameworks/base/%2B/refs/heads/main/core/java/android/app/Notification.java).
The binary JNI packet is at most 2,194 bytes and has
strict lengths, version and operation validation. Requests own their data.

The tag `asset_pipeline.local.v1` isolates this adapter's IDs from other native
notification producers in the app. Posting the same ID updates it. Cancel is
idempotent and can remove an owned notification even while permission is denied.
App-wide, channel and channel-group blocking are checked before post; a blocked
post reports PermissionDenied. These checks cannot eliminate a settings race.
Success means NotificationManager accepted the request, not that Android showed
it or the user read it. Do Not Disturb, lock-screen policy and user settings apply.
The content intent is immutable and opens the app's launcher without payloads.
Notifications use private lock-screen visibility and auto-cancel on activation.

All accepted operations complete once, deferred to the Android main looper.
The global Crystal limit of 64 spans all services, including permission callers.
Oversized, invalid public fields and unavailable/full submissions throw before
returning an Operation and have no callback. Manager work runs on a dedicated
serial JVM worker. Cancelled manager work finishes before its callback and does
not roll back a post/cancel that already happened. Terminal close cancels all
accepted operations, clears host bindings and drains the worker.

## Development proof

The explicit emulator-only permission-reset lane is:

```sh
ASSET_PIPELINE_ROOT=/absolute/path/to/asset_pipeline \
  AMBER_ANDROID_FIXTURE=notifications \
  bash scripts/test_native_android_app.sh emulator-5556 /tmp/amber-notification-proof
```

It installs only the test host, resets that emulator package's notification
permission using Android's documented testing commands, and drives the real OS
dialog. Test notifications/channels use contract-owned names and are removed
after the test. Notification configuration is debug-only in this lane; release
output remains opted out. Consult AssetPipeline's dated notification checkpoint
for actual results and unproved branches, rather than treating this command as
evidence that every supported device/version has passed.
