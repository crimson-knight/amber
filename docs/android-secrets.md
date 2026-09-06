# Android protected secrets — development adapter

This is a separate, optional service from ordinary SQLite-backed `Storage`.
Import `amber/native/android_secrets` and construct
`Amber::Native::Android::Secrets`. The host must initialize AssetPipeline's
canonical Android runtime with the application context before using it.
Plain `amber/native` does not import AssetPipeline or Android services.

```crystal
require "amber/native/android_secrets"

secrets = Amber::Native::Android::Secrets.new
operation = secrets.write("session-token", token) do |result|
  if result.is_a?(Amber::Native::ServiceError)
    # Handle the error without logging the token or secret identifier.
  end
end
```

`read` completes with a String, nil for an absent identifier, or ServiceError.
`write` and `delete` complete with nil on success or ServiceError. Empty strings
are stored values, distinct from an absent identifier. Operations and completion
callbacks have the same application-thread contract as the other native services.

## Protection and durability

- Android Keystore generates and retains a non-exportable, app-scoped AES-256
  key. Standard AES/GCM/NoPadding encrypts both secret identifiers and values as
  one authenticated vault. The provider generates a fresh nonce per write;
  the envelope version and app/vault identity are authenticated too.
- There is no plaintext index, user-supplied encryption key, software-key
  fallback, network synchronization or additional Android permission. Production
  encryption uses AndroidKeyStore; software keys appear only in JVM unit tests.
- Ciphertext lives under the application's credential-encrypted
  `noBackupFilesDir`. Android excludes this directory from automatic backup.
  Copying/restoring ciphertext without its original app Keystore key cannot
  recover the secrets. Reinstallation is not a supported persistence mechanism.
- This adapter is background-capable after the user's first device unlock.
  It is not biometric-gated, does not promise StrongBox or hardware backing,
  and is not a vault that locks on every screen lock. It rejects use in
  device-protected storage or before the user is unlocked.
- All directory, file, key and encryption operations run on a separate serial
  worker. A file lock serializes cooperating processes; a bounded authenticated
  read precedes mutation. Writes use AtomicFile, explicit file sync, committed
  ciphertext verification and directory sync before reporting success.
- If an existing vault loses its key, read/write/delete report Unavailable
  without generating a replacement or erasing data. Authentication, malformed
  data and filesystem failures report IO. Security access failures report
  PermissionDenied. Unknown formats are not migrated or reset silently.
- No recovery/reset/key-rotation API is provided yet. An app must treat key loss
  as a re-authentication/recovery state, not retry indefinitely or silently store
  the same secret in ordinary storage.

Keystore protects key extraction; it does not stop a compromised running app
from requesting decryption. Plaintext necessarily exists in Crystal/JVM memory,
and this garbage-collected implementation does not promise memory zeroization.
It also does not detect rollback to an older, valid ciphertext envelope.
Do not package server credentials or privileged shared secrets into the APK.

These choices follow Android's [Keystore model](https://developer.android.com/privacy-and-security/keystore),
[cryptography guidance](https://developer.android.com/privacy-and-security/cryptography),
and [backup exclusion contract](https://developer.android.com/identity/data/autobackup).
Directory exclusion is a platform guarantee, not evidence of a cloud backup
round-trip on a signed-in device.

## Limits and cancellation

Identifiers are nonempty UTF-8, at most 512 bytes. Values are UTF-8, at most
65,536 bytes. Supplementary characters and embedded NUL survive JNI byte-array
transport. A vault contains at most 128 entries and 1,000,000 encoded plaintext
bytes including lengths and identifiers. It is for small secrets, not files.

The 64 accepted-operation limit is shared with Storage and HTTP. Oversized or
unavailable transport submissions raise a typed error synchronously without a
callback. Accepted invalid input, capacity, key and IO errors complete
asynchronously. Invalid input/capacity never rewrites a valid vault.

Cancellation is idempotent and delivers one Cancelled completion after work has
ended. It is not rollback: a committed write may remain even if its completion
is Cancelled. Terminal session close cancels/drains accepted requests and stops
the secrets worker. Activity destruction/recreation does not close services;
Android process death cannot guarantee a final callback.

## Validation entrypoint

```sh
ASSET_PIPELINE_ROOT=/absolute/path/to/asset_pipeline \
  AMBER_ANDROID_FIXTURE=secrets \
  bash scripts/test_native_android_app.sh emulator-5554 /tmp/amber-secrets-proof
```

This builds both native ABIs and packages, executes canonical JVM and real
Android Keystore tests, then exercises the Amber adapter through JNI. The
`secrets-reopen` route only reads the preceding process's public test value;
the runner requires a different process ID. No real account secret is used or
shown on the screen. See the dated AssetPipeline proof checkpoint for actual
execution results; source tests alone are not runtime proof.
