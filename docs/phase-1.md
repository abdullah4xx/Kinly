# Phase 1 - Core + CLI on Arch

Status: **core acceptance passed on one machine (Linux); real two-device test
still needed.**

Date: 2026-11-18

## What was built

- `kinly-core` Rust crate:
  - Ed25519 identity (`identity.json`, device ID = hex public key).
  - Noise XX handshake (`snow`) with the handshake hash signed by the identity.
  - Anonymous mDNS advertisement (`_kinly._tcp.local.`) with a rotating ID.
  - SQLCipher storage for people, messages, transfers and settings.
  - Text messages with queueing, delivery/read receipts and typing indicators.
  - BLAKE3 file transfer with `.part` files, resume and hash verification.
  - Visibility (hiding) with the name never sent to a hidden peer.
  - Unique names based on identity creation time.
  - `kinly` CLI: `/list`, `/msg`, `/send`, `/history`, `/hide`, `/show`,
    `/whoami`, `/quit`.
- Tests: 17 unit tests + 5 end-to-end tests (messages, files, resume, hiding,
  duplicate names, packet capture).

## Acceptance evidence

| Criterion | Result |
|---|---|
| Two processes see each other and exchange messages | Passed: e2e test and a manual run of two `kinly` processes (`hello-from-alice` delivered) |
| A packet capture shows no plaintext | Passed: `a_packet_capture_contains_no_plaintext` proxies the TCP stream and asserts the message, `Alice` and `Bob` never appear in the captured bytes |
| A 1 GiB file transfers without corruption (matching hash) | Passed: `one_gigabyte_file_transfers_without_corruption` (1 GiB, BLAKE3 match, 329 s on this machine) |
| The transfer resumes after an interruption | Passed: `a_file_transfer_resumes_after_interruption` (kills the receiver at 1 MiB, restarts it, resume offset verified, hash matches) |
| Turning visibility off hides the name and conversation | Passed: `a_hidden_device_never_sends_its_name` (after a restart the hidden device only sends `VISIBILITY(false)`, no `PEER_UP`) |
| Duplicate name is rejected | Passed: `two_nodes_exchange_messages_files_and_hide` (third device named "Alice" is rejected by the older identity) |
| Core tests cover crypto, hiding, names and file transfer | `cargo test`: 17 unit + 5 e2e tests green |

## Reproduce

```bash
cd core
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
cargo test --test e2e one_gigabyte -- --ignored --nocapture   # 1 GiB check
```

Manual check with two terminals:

```bash
cargo run --bin kinly -- --name Abdullah
cargo run --bin kinly -- --name Mohamed
```

## Pending for the real-device checklist

- Two Arch machines (or Arch + Android after Phase 2) on the same Wi-Fi/hotspot.
- Third-party capture (Wireshark) on the LAN to confirm no plaintext for a
  longer session.
- Interrupt a 1 GiB transfer by unplugging Wi-Fi and confirm resume on both real
  devices.
- Confirm the mDNS advertisement is visible as `kinly-<random id>` and rotates.
