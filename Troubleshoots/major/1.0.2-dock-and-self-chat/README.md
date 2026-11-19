# 1.0.2 — bottom dock and self-chat cleanup

**Released:** 19 November 2026
**Build:** `1.0.2+3`, commit `54cb106`
**Status:** APK published; on-device confirmation pending

## What changed

- **Bottom dock fixed.** `Scaffold.bottomNavigationBar` was measuring a
  full-height `Center`, so the dock floated in the middle of the screen and
  covered content. `Center(heightFactor: 1)` shrinks it to the dock height,
  and the bar now sits at the bottom as intended. See
  [`../../docs/01-bottom-navigation-floating.md`](../../docs/01-bottom-navigation-floating.md).
- **Self-chat labelled.** A chat whose peer id equals this device's id now
  shows `(You)` next to the name in the chat list and the chat header.
- **No hide button on self-chats.** The visibility toggle is hidden for that
  one conversation; the app still exposes the per-person toggle for other
  people, as required by the plan.

## Release

- Page: <https://github.com/abdullah4xx/Kinly/releases/tag/apk-1.0.2>
- APK:
  <https://github.com/abdullah4xx/Kinly/releases/download/apk-1.0.2/kinly-1.0.2-arm64.apk>
- Size: 28,863,572 bytes
- SHA-256:
  `58ef54b9e386ad8809948c3be2b08dfca79ce084f98e8eb3ad83dfbb39ddfeb1`
- Manifest check with `pyaxmlparser`: `app.kinly.chat`, `versionName=1.0.2`,
  `versionCode=3`, label `Kinly`.
- Pre-release, arm64, debug-signed. Installs over 1.0.1 and keeps identity
  and messages.

## CI

- CI: run `44516645006` (green).
- APK: run `44516645008` (green).

## Verification checklist (on device)

1. Install over 1.0.1 and check `dumpsys package` reports `1.0.2` / `3`.
2. Home: the dock is at the bottom, not in the middle; the empty state and
   chat rows are not covered.
3. Settings: scroll to the end; swatches, custom colour, language, hidden
   people, and About stay clear of the dock.
4. Self-chat: shows `abdullah (You)` (or the localised `(أنت)`), with no eye
   button in the list or the header.
5. Arabic/RTL: dock order stays mirrored and the `(You)` label reads
   correctly.
6. 1.0.1 → Settings → About → Check for updates offers this build.
