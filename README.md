# Kinly

A private chat app for the family. It works over the local network (Wi-Fi or a
phone hotspot) with no internet and no server. All messages and files are
end-to-end encrypted.

**Author:** Abdullah ([@abdullah4xx](https://github.com/abdullah4xx))

`PLAN.md` is the source of truth for scope, decisions and phases.
`ui-reference.png` is the reference design for the UI.

## Platforms

- Android (plain APK, primary)
- Arch Linux (secondary)

## Repository layout

```
core/                 Rust core (protocol, crypto, discovery, storage, files) + tests
app/                  Flutter app (android + linux); all UI lives here
  android/            Kotlin system glue (foreground service, Bluetooth, MulticastLock)
docs/                 protocol spec and design decisions
.github/workflows/    ci.yml and release.yml
PLAN.md
ui-reference.png
```

## Development

Requirements: Flutter 3.50.0, Rust stable, Android SDK/NDK for Android builds.

```bash
# Rust core
cd core
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test

# Flutter app
cd app
flutter pub get
flutter analyze
flutter test

# Run on a connected Android device
flutter run

# Build a release APK (requires android/key.properties, see below)
flutter build apk --release
```

## Core CLI (Phase 1)

The Rust core ships a terminal client that exercises discovery, the encrypted
handshake, messages, files and hiding without the Flutter UI:

```bash
cd core
cargo run --bin kinly -- --name Abdullah
```

On the second machine (or a second terminal):

```bash
cargo run --bin kinly -- --name Mohamed
```

They find each other over mDNS on the same Wi-Fi/hotspot. If mDNS is blocked,
pass `--no-mdns --peer 192.168.1.20:41234` (or use `--peer 127.0.0.1:PORT` for
two processes on one machine; the first process prints its port).

Commands: `/list`, `/msg <name> <text>`, `/send <name> <path>`,
`/history <name>`, `/hide <name>`, `/show <name>`, `/whoami`, `/quit`.

The data directory defaults to `~/.local/share/kinly` and can be changed with
`--data`. It contains the Ed25519 identity, the Noise key, the SQLCipher
database and its key; all files are mode 0600. Deleting it gives the device a
new identity.

## Signing

Release builds are signed with the owner's keystore. The keystore and its
passwords are **never committed**. GitHub Actions reads them from repository
secrets (PLAN.md section 9.3):

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | keystore file, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |

For local release builds, create `app/android/key.properties`:

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=/absolute/path/to/keystore.jks
```

**If the keystore is lost, the app cannot be updated on devices that already
have it installed.**

## Releases

CI runs on every push and pull request. Pushing a tag such as `v0.0.1` builds
and signs the Android APK and the Linux archive, then publishes both on the
repository's Releases page.

## License

MIT, see `LICENSE`.
