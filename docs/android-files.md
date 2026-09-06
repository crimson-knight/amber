# Android app-private files — development adapter

Import `amber/native/android_files` and construct `Amber::Native::Android::Files`
to implement the shared Files interface on Android. The application must install
AssetPipeline and initialize its canonical host with the application context.
The optional adapter does not add an Android dependency to plain `amber/native`.

```crystal
require "amber/native/android_files"

files = Amber::Native::Android::Files.new
operation = files.write("drafts/current.bin", bytes) do |result|
  # nil means committed; a ServiceError requires explicit application handling.
end
```

`read` returns owned `Bytes` or ServiceError. An absent file reports IO because
the shared Files interface does not have a missing-file result; a successful
zero-byte file returns an empty byte slice. `write` and `delete` return nil on
success or ServiceError. Deleting an absent file is successful and idempotent.
Writes create missing parent directories. Directory deletion is rejected;
this is not a recursive-delete API.

## Location and security model

Files live under `context.filesDir/asset_pipeline_files_v1`, not external storage,
shared documents or the secret vault. No storage permission, FileProvider URI
grant or document-picker permission is requested. The location follows
[Android app-specific internal storage](https://developer.android.com/training/data-storage/app-specific).
Android removes app-specific files on uninstall. Ordinary files may participate
in backup according to the host's explicit backup policy; they do not inherit
the Secrets adapter's unconditional no-backup exclusion.

These are ordinary app-private binary files, not separately encrypted secrets.
Use the Secrets adapter for tokens. The app-private sandbox is not a defense
against code already running with the application's UID or a compromised OS.
Credential-encrypted storage is required; use before first user unlock or with
a device-protected context reports Unavailable. That branch is enforced but
has not yet received a pre-first-unlock device test.

The Kotlin worker calls a small native POSIX backend that never enters Crystal.
It opens each path component relative to an open directory descriptor using
`openat`/`mkdirat` and `O_NOFOLLOW`, and uses `fstatat`/`fstat` to require a regular,
single-link file. These are public [NDK C library APIs](https://developer.android.com/ndk/guides/stable_apis),
checked against the pinned API 31 headers for both supported native ABIs.
There is no canonical-path-check followed by an unrestricted absolute-path write.
Symlinks, hard-linked files, directories and special files are rejected. Nonblocking
opens prevent a FIFO from stalling a file operation before its type is checked.

## Path and data limits

- Paths are strict UTF-8 relative paths, at most 1,024 bytes, with at most 32
  components of at most 255 bytes each. Names are not normalized or URL-decoded.
- Empty paths/components, leading/trailing slashes, `.`/`..`, backslashes,
  colons, ASCII control characters and NUL are invalid. Components beginning
  `.ap-` are reserved for the backend's lock and temporary file.
- Values are arbitrary binary bytes, at most 1 MiB per write/read. No UTF-8
  validation is applied to data. Supplementary characters in filenames and
  every byte value in content survive the byte-array JNI transport.
- This API is not streaming, append, a large-media transfer API or a user-selected
  document API. Those require separate contracts. There is no per-vault aggregate
  quota; disk exhaustion reports IO rather than silently truncating content.

## Writes, cancellation and lifecycle

All filesystem work runs on a dedicated serial JVM worker. A namespace file lock
serializes cooperating processes; lock acquisition fails after five seconds of
contention instead of waiting forever. Each call closes every native file
descriptor and frees its buffers before returning. It retains no JNI reference.

Writes create a private same-directory temporary file, write all bytes, sync
and close it, atomically rename it over the selected regular file, then sync
the parent directory before success. Newly created parent directories are also
synced. A read ignores an interrupted write's temporary file; deleting a file
does not resurrect that temporary content. A later write removes only the
reserved regular, single-link temporary file. Unsafe temporary/lock paths fail.

Before-commit failures preserve the old file. An error after rename can mean
the new file exists despite an IO result; no rollback is promised. Empty parent
directories may remain after a failed write. Multi-file transactions, arbitrary
power-loss guarantees and hostile same-UID filesystem mutation are not promised.

The accepted-request limit of 64 is shared with storage, secrets and networking.
Oversized/unavailable submissions raise synchronously without returning an
Operation or invoking a callback. Accepted validation/IO errors complete once,
asynchronously on the Android main looper. Requests own their input bytes.

Cancellation is idempotent, waits for work to end and reports Cancelled; it does
not undo a committed write/delete. Terminal `closeSession` cancels/drains accepted
requests and stops the worker. Activity recreation does not close the service.
Process death cannot guarantee a completion or final lifecycle callback.

## Proof entrypoint

```sh
ASSET_PIPELINE_ROOT=/absolute/path/to/asset_pipeline \
  AMBER_ANDROID_FIXTURE=files \
  bash scripts/test_native_android_app.sh emulator-5556 /tmp/amber-files-proof
```

The runner checks the exact C backend on the host, canonical JVM tests, real
Android filesystem behavior, the Amber adapter and a separate-process read-only
restoration route. Android denied hard-link creation in the test app domain, so
the report distinguishes that platform restriction from host proof of the
backend's hard-link rejection. See the dated AssetPipeline file checkpoint for
actual evidence and the still-open full Android support gates.
