# 1.1.3 — signing, quiet notifications, app lock, camera and self chat

**Released:** 27 November 2026
**Build:** `1.1.3+4`, commit `45ae878`
**Status:** APK published; on-device confirmation pending

## What changed

- **Signing fix.** Release builds now sign with the stable keystore stored in
  GitHub Secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`). Both CI workflows decode it and
  fail fast when the secrets are missing; the APK workflow verifies the signed
  artifact with `apksigner` and publishes a rolling pre-release tagged
  `apk-1.1.3`.
- **Quiet background notification.** The foreground service now uses a channel
  with `IMPORTANCE_MIN`, no sound, no vibration, no badge and no timestamp
  (`kinly_service_quiet_v2`). A persisted "Receive messages in background"
  setting (default on) controls the service through the
  `app.kinly.chat/system` channel.
- **Biometric app lock.** New `app.kinly.chat/lock` channel backed by AndroidX
  `BiometricPrompt` with the device-credential/PIN fallback. The gate lives in
  the root gate; the session unlocks for two minutes after backgrounding.
- **In-app updater.** The updates page streams the APK from GitHub with progress,
  verifies the SHA-256 from the `.sha256` sidecar and installs through the
  system installer (`FileProvider` + `ACTION_VIEW`).
- **Camera tab.** Takes a photo and sends it through the encrypted file
  transfer, scans a Kinly QR code, or runs OCR on a photo and copies the text.
- **Self chat.** The node keeps a local self person row and stores messages sent
  to itself as local outgoing echoes. The chat list and header label it with
  `(You)` / `(أنت)` and never offer hide or call actions.

## Release

- Page: <https://github.com/abdullah4xx/Kinly/releases/tag/v1.1.3>
- APK:
  <https://github.com/abdullah4xx/Kinly/releases/download/v1.1.3/kinly-1.1.3-arm64.apk>
- Size: 128,502,192 bytes
- SHA-256:
  `35e35af2b208066b059b77f15e3cedd4f535ce2cb8e2602d76a00d7f6c550b37`
- Also published as the rolling pre-release
  <https://github.com/abdullah4xx/Kinly/releases/tag/apk-1.1.3>.

## CI

- CI: run `45975068734` (green).
- APK: run `45975068637` (green, signed with the stable key and verified with
  `apksigner`); the APK was uploaded to this release from that build and the
  checksum was re-verified locally.
- The tag-triggered Release workflow hit a transient Maven Central `429` while
  resolving Gradle plugins; the same APK from the green APK run was used for
  the manual publish instead of re-running the build.

## Verification checklist (on device)

1. Install the `apk-1.1.3` build over 1.0.2; because the signing key changed,
   Android shows a data-loss warning and the identity may be reset.
2. Quiet notification: with the app closed, a message from a peer arrives and the
   notification stays silent.
3. Settings -> Notifications: toggle "Receive messages in background".
4. Settings -> Account: toggle the app lock, unlock with fingerprint and with
   the device PIN fallback; resume from background re-locks after two minutes.
5. Camera: take a photo, pick a recipient, send; scan a Kinly code; OCR a page.
6. People: visibility switch moves here; the chat list no longer shows it.
7. Self chat: open the self conversation, send a message, expect an outgoing
   bubble.
8. Settings -> Updates: check, download and install over an older build.
9. Basic call: two devices on the same hotspot, voice call, answer, hangup.
