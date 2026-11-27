# Kinly 1.1.3 device inspection report

Date: 2026-11-27
Devices inspected:

- OPPO A38, Android 15, `app.kinly.chat`, Arabic UI, portrait phone layout.
- Samsung Galaxy Tab A7 Lite (`SM-T509`), Android 12, `app.kinly.chat`, English UI, landscape tablet layout, one-column phone-style layout.

Screenshots are saved under:

`Troubleshoots/major/1.1.3-quiet-notifications-self-chat/screenshots/`

- Phone (`oppo-a38/`): Chats, self chat, chat, Account, Security, Settings, Appearance, People, Notifications, Updates, About, Danger zone, Camera.
- Tablet (`galaxy-tab-a7-lite/`): Chats, Account, chat, Settings, Appearance, People, Notifications, Updates, About. Tablet shots were taken before rebuilding; the tablet went `offline` in `adb` while reinstalling the fixed build.

Note: this model cannot render image input in the current session, so screenshots were captured for the user/repo but visual QA was done from Android view-hierarchy output, logs, and code inspection, not by reading pixels back. The mobile-mcp screenshot tool also reports `Cannot read image` in this model.

## Bugs found and fixed

### 1. Voice/video call crashed before connecting

**Found on tablet:** tapping `Call` opened WebRTC then returned to the launcher (`SIGABRT`).

Crash reports (`app.kinly.chat`, thread `signaling_threa`, `libjingle_peerconnection_so.so`):

```text
Fatal error in: pc/peer_connection.cc
Check failed: !IsUnifiedPlan()
AddStream is not available with Unified Plan SdpSemantics. Please use AddTrack instead.
Fatal signal 6 (SIGABRT)
```

**Fix:** `app/lib/screens/call.dart` no longer calls `pc.addStream(stream)`. Each audio/video track is attached with `pc.addTrack(track, stream)`.

### 2. Calls did not reliably reach `ongoing` / connect

Additional call-flow issues found in `app/lib/state/node_controller.dart` + `app/lib/screens/call.dart`:

- Incoming offers were ignored when no `CallState` existed; `startIncomingCall` was never called from `_handleCallSignal`. Fixed by starting `CallPhase.incoming` on `type: 'offer'`.
- Offer payload did not say whether the call was voice or video. Added `'video': widget.video`.
- Outgoing calls received `answer` but did not call `setRemoteDescription(answer)`. Added answer application in `_syncSignals()`.
- ICE candidates could arrive before the remote description or accept. Added a `candidates` queue and applied candidates after `setRemoteDescription`.
- `lastSignal` could be overwritten by `candidate`, losing the SDP offer. Added `offerSdp`.
- Hangup is handled for incoming/outgoing calls.

**Still to verify on device after reinstalling the fixed APK:** two-device voice call connects, both sides hear audio, mute works, end-call works, video call works on Android, and no `libjingle` SIGABRT remains. (The fixed APK was built green by CI; reinstall/retest was blocked because the tablet went `offline`.)

### 3. Received images showed only a file name; received files were hidden in app-private storage

**Found:** incoming file bubbles rendered only `transfer.name`; incoming data was stored only at `/data/user/0/app.kinly.chat/files/kinly/downloads/`, which is not reachable in a normal file manager.

**Fixes:**

- `app/lib/screens/chat.dart`: completed incoming image transfers render an `Image.file` preview inside the chat bubble (`png`, `jpg`, `jpeg`, `webp`, `gif`, `bmp`, `heic`, `heif`), with a broken-image fallback; tapping a completed transfer copies the saved/openable path.
- `app/lib/state/node_controller.dart`: on incoming `file_complete`, call `saveToDownloads(...)` and remember `transfer.savedPath`.
- `app/lib/util/system.dart`: new Android `app.kinly.chat/system` `saveToDownloads` method.
- `app/android/app/src/main/kotlin/app/kinly/chat/MainActivity.kt`: Android `MediaStore.Downloads` insert on Android 10+; public `Downloads/Kinly` fallback on Android 8/9; `IS_PENDING` handled; `MIME_TYPE` set; safe display names.
- `app/android/app/src/main/AndroidManifest.xml`: `WRITE_EXTERNAL_STORAGE` only `maxSdkVersion=28`; Android 8/9 requests it at runtime. Android 10+ does not need legacy storage permission for `MediaStore.Downloads`.
- Kinly still keeps its own internal copy for rendering; the user-visible copy is saved to **Android `Downloads/Kinly`** (not a Kinly app folder).

### 4. Yellow underlines in Settings

**Found:** user observed yellow text underlines under Settings content on every page. No explicit `TextDecoration.underline` or yellow decoration was found in source. Settings also inherited default text decoration.

**Fix:** `app/lib/theme/tokens.dart` sets `TextDecoration.none` in `ThemeData.textTheme`. (Device re-screenshot after reinstall still pending.)

### 5. Black accent was rejected; no color banner; `accentTooClose` blocked colors

**Found:** `app/lib/state/settings.dart` returned early if `accentTooClose(color)`, `AppSettings.load()` replaced too-close stored accents with `Tokens.defaultAccent`, custom picker only called `setAccent` when not too close, no `Black` preset, no full accent color banner.

**Fixes:**

- `AppSettings.setAccent(...)` no longer rejects any color.
- `AppSettings.load(...)` no longer silently resets stored accent.
- Custom color picker always applies color; `colorTooClose` remains a warning, not a block.
- `Tokens.accentPresets` adds `Black` (`#000000`).
- `_ColorBanner` added in `app/lib/screens/settings/appearance_page.dart`, full-width accent color banner with `readableOn(accent)` text.
- `app/test/strings_test.dart` updated: too-close colors are warnings, not rejection.

## Verification already run

- `flutter analyze --no-fatal-infos`: 25 issues, all pre-existing `deprecated_member_use` infos; no errors/warnings from these changes.
- `flutter test`: **16/16 passed**.
- GitHub APK workflow for the fixed build: **green**, signed + checksum + rolling `apk-1.1.3` pre-release.
- `git push origin main`: pushed.

## Not yet proven / still open

- Two-device call test after reinstalling fixed APK was blocked by tablet `adb` going `offline`.
- Cannot visually inspect screenshots in this model; images are saved but not rendered to me.
- Yellow-underline removal not re-screenshot-verified after rebuild.
- `Downloads/Kinly` re-screenshot/file-manager verification pending on device.
- Kotlin `MainActivity.saveToDownloads` compiled in CI; runtime MediaStore copy not yet run on Android 15/12 devices.
- Android 8/9 `WRITE_EXTERNAL_STORAGE` runtime path not tested (no API 28 device connected).

## Suggested next device test

1. Reinstall `kinly-1.1.3-arm64.apk` on both devices.
2. Send a PNG/JPG from phone to tablet; verify preview in chat + file in `Downloads/Kinly`.
3. Voice call tablet -> phone; verify no crash, incoming ring, answer, two-way audio, mute, end.
4. Settings -> Appearance -> black accent; verify no rejection + color banner + no yellow underlines.
