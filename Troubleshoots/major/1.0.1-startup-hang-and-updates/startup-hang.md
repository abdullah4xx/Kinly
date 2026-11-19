# 02 — App hangs forever on the "Starting Kinly..." splash

**Severity:** critical — the app was unusable after the first successful run.
**Status:** fixed and shipped in **1.0.1**.
**Reported by:** owner, fresh install of 0.0.1 that worked once, then stayed
on the splash on the next launch.

## Symptoms

- The dark splash with "Starting Kinly..." stayed forever, spinner included.
- No error screen and no way to retry.
- Reinstalling or clearing data temporarily changed the behaviour, which
  pointed at the saved identity / node-start path rather than the Flutter
  widget tree.

## Root cause

Two problems stacked up:

1. **mDNS blocked the node command loop.** `run_node` called
   `Discovery::start(...)` / `browse()` synchronously before entering its
   `tokio::select!` loop. Opening multicast sockets can block (or take very
   long) on Android when multicast is filtered by the Wi-Fi stack or a VPN.
   While that call was stuck, the actor never polled `cmd_rx`, so
   `online_peers()` and `people()` oneshot replies never arrived.
2. **The UI waited for the first refresh before repainting.** In
   `NodeController.start`, `node` was assigned but `notifyListeners()` only
   ran in `finally`, after `await refresh()`. With `people()` blocked, the
   splash never rebuilt even though the node handle existed.

## Fix (shipped in 1.0.1)

- `core/src/node.rs`
  - mDNS init moved to `tokio::task::spawn_blocking` inside a spawned task,
    guarded by a 10-second `tokio::time::timeout`.
  - The result is delivered over an `mpsc` channel and picked up by a new
    `select!` branch, so the command loop is served immediately.
  - Discovery stays optional; failure emits a non-fatal `Event::Error`.
- `app/lib/state/node_controller.dart`
  - `startNode` has a 25-second timeout and retries once with
    `enableMdns: false` if the first attempt times out.
  - `notifyListeners()` runs right after the node handle is assigned, before
    `refresh()`, so Home appears without waiting for the network.
  - `refresh()` has an 8-second timeout; a stuck `people()` can no longer
    hold the `_busy` flag or the start path.
- `app/lib/app.dart`
  - The fatal screen retry now awaits `controller.reset()` and starts again
    with the known name (or returns to the welcome screen for a fresh
    identity).
  - A returning device starts the node immediately; a fresh device starts it
    from the welcome screen after the name is entered.

## Verification

- Rust: `cargo fmt`, `cargo clippy --all-targets -- -D warnings`,
  `cargo test --lib` (22 tests).
- Flutter: `flutter analyze --no-fatal-infos`, `flutter test` (10 tests).
- Device: 1.0.1 launched successfully on the OPPO A38 and reached the chat
  list (`screenshots/home-after-startup-fix.png`).
- APK: GitHub Actions run `44327510454` (green), asset
  `kinly-1.0.1-arm64.apk`.

## Follow-up

If a future device still hangs, the app now lands on the retryable error
screen after at most 25 seconds instead of spinning forever. The native
`startNode` call that timed out is abandoned; the retry opens a second node
without mDNS.
