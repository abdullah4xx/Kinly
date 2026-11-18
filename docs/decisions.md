# Design decisions

Decisions made while building Kinly, with the reason. `PLAN.md` holds the
original requirements.

## Product and repository

| Decision | Value | Reason |
|---|---|---|
| Package / application ID | `app.kinly.chat` | Approved by the owner; stable before the first release |
| Repository visibility | public, MIT | Owner chose open source |
| Author credit | Abdullah ([@abdullah4xx](https://github.com/abdullah4xx)) in `Cargo.toml` and source headers | Owner request |
| Branching | `main`, small commits, PR per phase | `PLAN.md` section 13 |
| Releases | GitHub Actions on version tags | `PLAN.md` section 9 |

## Stack

| Area | Choice | Reason |
|---|---|---|
| UI | Flutter 3.50.0, Android + Linux | Plan default; one UI for both platforms |
| Core | Rust (cdylib + CLI) | Memory safety, good crypto libraries, reused by both platforms |
| Async runtime | Tokio | Standard for networking and file I/O |
| Handshake | Noise XX via `snow` | Established protocol, no custom crypto |
| Identity | Ed25519 via `ed25519-dalek`; device ID = hex public key | Stable identity, verifiable signature |
| Discovery | mDNS via `mdns-sd`, anonymous rotating instance ID | No names on the wire before encryption |
| Storage | SQLCipher via `rusqlite` (bundled SQLCipher) | Encrypted at rest, single-file DB |
| Files | BLAKE3 hash, `.part` + rename | Fast hash, safe resume and no partial files in the library |
| Calls | WebRTC (Phase 3) | The only realistic way to do NAT-free LAN audio/video |

## Security

- The Noise handshake hash is signed together with a domain prefix
  (`kinly-hello-v1`) and the Ed25519 identity, so a captured handshake cannot be
  replayed for a different identity.
- A device hidden by the user never sends its name, even during the probe: the
  probe always has an empty name, and the visibility decision is made before the
  full HELLO.
- The advertised mDNS ID is random and rotates every 10 minutes, so a passive
  observer cannot track a device by its beacon.
- Keys and the database key are written with mode 0600; the keystore is never
  committed and is read from GitHub Actions secrets.

## Core behaviour choices

- Hiding is one-directional, per `PLAN.md` section 6.
- Writing to a person we hid automatically turns our toggle for them back on.
- Duplicate names are resolved by identity creation time: the older device keeps
  the name and sends `ACK(NameTaken)`; the newer one reports the rejection.
- Simultaneous dials keep the session initiated by the device with the smaller
  device ID, so both sides converge on one TCP connection.
- Messages and file offers to offline peers stay in the encrypted database and
  are flushed when the peer comes online.
- The CLI (`core/src/bin/kinly.rs`) is a development and Phase 1 acceptance tool;
  the Flutter app is the product.
