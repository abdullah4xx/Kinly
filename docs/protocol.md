# Kinly wire protocol (v1)

This document describes what `kinly-core` puts on the wire. Everything after
the Noise handshake is encrypted and authenticated; the only plaintext an
observer can see is TCP framing bytes.

## Transport

- TCP, one connection per pair of devices. Either side may dial; simultaneous
  dials are resolved so both sides keep the same session (the device with the
  smaller device ID keeps the session it initiated).
- Every message is a 4-byte big-endian length followed by that many bytes of a
  Noise ciphertext. The length must be between 1 and 65,535 bytes (about 64 KiB).
- Discovery uses mDNS (`_kinly._tcp.local.`). The advertised instance is
  `kinly-<random id>`; the random ID rotates every 10 minutes. No name, no
  device ID and no stable identifier is advertised.

## Handshake

1. Both sides run **Noise XX** (`Noise_XX_25519_ChaChaPoly_BLAKE2s`) with a
   per-install static X25519 key (`noise-key.json`, mode 0600).
2. Each side sends a **probe HELLO** with an empty name. The HELLO carries the
   protocol version, the Ed25519 device ID, the identity creation time and a
   signature over `"kinly-hello-v1" || Noise handshake hash`. The signature
   binds the device identity to this exact encrypted session.
3. Both sides verify the probe signature against the device ID, which is the
   hex-encoded Ed25519 public key.
4. A device that has hidden the peer from itself stops here: it sends
   `VISIBILITY(false)` and closes. It never sends its name.
5. Otherwise each side sends a **full HELLO** (same fields, with its name and
   optional avatar). A peer that receives `VISIBILITY(false)` instead records
   that it is hidden and closes.
6. Unique names: if the peer's name is already bound to a different device ID,
   the **older** identity sends `ACK(NameTaken)` and closes; the newer device
   reports "name already taken" locally.
7. Both sides exchange `PRESENCE(Online)` and the session is up.

If a message is written to a person that is currently hidden by us, the
visibility toggle for that person is turned on first, then the message is sent.

## Control payloads

All payloads are JSON structures serialized with `serde_json` inside the
encrypted frame (see `core/src/protocol.rs`).

| Payload | Fields | Meaning |
|---|---|---|
| `Hello` | version, device_id, name, avatar, identity_created_at, signature | Identity exchange (see above) |
| `Presence` | state (`online`/`offline`) | Peer is online |
| `Msg` | id, body, sent_at | Text message |
| `Ack` | message_id, state (`delivered`, `read`, `failed`, `name_taken`) | Delivery/read receipt or name rejection |
| `Typing` | typing | Typing indicator |
| `FileOffer` | transfer_id, name, size, blake3 | File metadata |
| `FileAccept` | transfer_id, offset | Receiver accepts, possibly resuming at `offset` |
| `FileCancel` | transfer_id, reason | Transfer cancelled |
| `Visibility` | visible | Hider tells the peer whether it is hidden |
| `CallSignal` | call_id, payload (opaque JSON) | WebRTC signalling (Phase 3) |

## Frames

`Frame::Chunk { transfer_id, offset, last, data }` is a file chunk (32 KiB).
`Frame::Control(payload)` carries everything else. Chunks are ordered; the
receiver rejects an offset that does not match its current write position.

## Message queue and receipts

- A sent message is stored locally with state `queued`, then `sent` when it is
  written to an open session. When the session comes up, all queued messages for
  that peer are flushed in order.
- The receiver stores the message and answers `ACK(Delivered))`.
- Opening a conversation and marking it read sends `ACK(Read)` for received
  messages.
- Message IDs are UUIDv4; duplicates are ignored by the primary key.

## Files

1. The sender hashes the file with BLAKE3, stores the transfer row and sends
   `FileOffer`.
2. The receiver opens `<transfer_id>.part` in its downloads directory, resumes
   from the existing size if a partial file is present, and replies with
   `FileAccept { offset }`.
3. The sender streams `Chunk` frames starting at `offset`, updating progress in
   its database.
4. The receiver enforces the announced size, computes BLAKE3 while writing, and
   renames the `.part` file into place only when size **and** hash match.
5. On any failure the `.part` file stays in place; the next offer resumes from
   its length (unless it is larger than the announced size, in which case it is
   restarted from zero).

File names are sanitized (no directory components, no control characters) and
never overwrite an existing file: `photo.jpg` becomes `photo (1).jpg`.

## Visibility semantics

- Hiding is one-directional: the hider still sees the other person; the hidden
  person's app hides the hider's name and conversation.
- Messages already stored on the hidden side remain in the encrypted database
  and reappear when the toggle is turned back on.
- A hidden device never receives the hider's name, even if the hiding device
  initiates the connection.

## Storage

- SQLCipher database `kinly.db`; the key is 32 random bytes in `db.key`.
- Files are `identity.json` (Ed25519), `noise-key.json` (X25519), `db.key` and
  `kinly.db`, all created with mode 0600 inside the data directory.
- Tables: `settings`, `people`, `messages`, `transfers`.

## Limits

- Protocol version 1; unknown versions are rejected.
- One-to-one only (no groups).
- Linux/Android interoperate; iOS is out of scope.
