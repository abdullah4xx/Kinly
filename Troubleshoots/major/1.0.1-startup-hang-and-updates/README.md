# 1.0.1 — startup hang fix and in-app updates

**Released:** 19 November 2026
**Build:** `1.0.1+2`, commit `545f4f6` (README link bumped in `005e862`)
**Status:** shipped and verified on the owner's phone (OPPO A38, Android 15)

This folder collects the two changes that made 1.0.1 a major update:

| Document | Scope |
|----------|-------|
| [`startup-hang.md`](startup-hang.md) | The app no longer stays on the splash screen forever |
| [`in-app-updates.md`](in-app-updates.md) | Settings → About checks GitHub Releases for a newer APK |

## Evidence

- `screenshots/home-after-startup-fix.png` — the app reached Home on 1.0.1
  (the floating dock in that shot is issue 01, fixed afterwards).
- GitHub Actions: CI `44327510379`, APK build `44327510454`.
- Release asset:
  <https://github.com/abdullah4xx/Kinly/releases/download/apk-1.0.1/kinly-1.0.1-arm64.apk>
- SHA-256:
  `40bc81ffaf2be3a781aea46c83362bb13758ef15452c81c6f751dd0907c2ad68`
- APK metadata: 28 MB, `package app.kinly.chat`, `versionName=1.0.1`,
  `versionCode=2`, label `Kinly`, `lib/arm64-v8a/libkinly_core.so`.

## Test summary

- Rust: 22 tests, clippy clean.
- Flutter: 10 tests, `flutter analyze --no-fatal-infos` clean.
- Device: clean launch reached the chat list without hanging.
- Remaining blockers at release time: signing secrets for a production
  key, and a second phone for two-device messaging tests.

## Related ordinary issues

- The dock layout bug found during this verification round:
  [`../../docs/01-bottom-navigation-floating.md`](../../docs/01-bottom-navigation-floating.md)
- Device tooling used for the screenshots:
  [`../../docs/04-device-testing-setup.md`](../../docs/04-device-testing-setup.md)
