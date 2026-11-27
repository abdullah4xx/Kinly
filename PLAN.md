# PLAN.md — Kinly: an offline, local-network chat app

**Kinly** is a private chat app for the owner and their family. It works over the local network (Wi-Fi or a phone hotspot) with **no internet and no server**.

- **Platforms:** Android (plain APK, primary) and Arch Linux (secondary).
- **Implementer:** an AI agent. The owner reviews and tests on real devices.
- **Build and release:** GitHub Actions. Build output is uploaded to the **owner's own GitHub repository** (see section 9).
- **Communication:** the owner speaks Egyptian Arabic. Reply to the owner in Arabic. Keep code, comments, docs, commit messages and PRs in English.

---

## 0. Working folder contents

```
PLAN.md             <- this file
ui-reference.png    <- reference UI design image (see section 4). Must sit in the same folder.
```

- **Owner:** save the reference design image as `ui-reference.png` next to this file. If the name differs, update it here.
- **Agent:** open `ui-reference.png` and consult it for every UI task. The image is the final authority on visual details; section 4 only complements it.

---

## 1. Fixed decisions

- No central server. Devices connect directly to each other (peer-to-peer).
- Name: **Kinly**. Suggested package id: `app.kinly.chat` (changeable). Suggested repo name: `kinly`.
- Distribution: plain APK, sideloaded onto family devices. **Play Store publishing is deferred and out of scope.**
- Top priority when choosing technology: **full UI customization**.
- **Video calls on Android only.** Arch does not need video.
- **Bluetooth is a fallback only**, for when no Wi-Fi is available. Wi-Fi and hotspot come first.
- All messages and files are **end-to-end encrypted**.
- **Names are unique**: no two users may share a name.
- The per-person visibility toggle is **ON by default**.
- **UI:** dark neumorphism (soft shadows) as in `ui-reference.png`. **The accent color (red in the image) must be changeable in Settings.**
- Builds run on **GitHub Actions** and are uploaded to the owner's GitHub.

## 2. Open decisions (default is used unless the owner answers)

| Decision | Default |
|---|---|
| UI technology | **Flutter** for the UI + a **Rust core** for networking and crypto (alternative: Kotlin + Jetpack Compose, Android only) |
| Visibility toggle location | **People page** in 1.1.3 (was: eye icon per chat-list row, also in the chat header) |
| Arch calls | **No calls** in the first version |
| Messages to an offline peer | **Queued and delivered when the peer returns** |
| Groups | **Not in the first version** (one-to-one chat only) |
| Language | **Arabic + English with full RTL support** |
| Repository visibility | **Private** on the owner's GitHub |
| Camera tab in the bottom bar | **In 1.1.3** as the fourth dock icon (was: deferred) |

---

## 3. Core behavior

1. First launch shows a **welcome screen**: the user types a name (and optionally a profile picture).
2. The name appears to everyone on the network automatically, and they appear to the user. The list updates live.
3. Each person is a row in the **chat list**, stacked vertically like WhatsApp.
4. Next to each person is a **visibility toggle**. If the user turns it off for Mohamed, the user (name **and** conversation) disappears completely from Mohamed's side.
5. Text messages, fast file transfer, voice and video calls (video on Android only), all encrypted.

---

## 4. UI specification (reference: `ui-reference.png`)

### 4.1 General style
- **Dark neumorphism:** a dark slate background (never pure black), raised or inset elements with soft shadows (light from the top-left, shadow to the bottom-right), large rounded corners.
- A **single accent color** (red in the image) for interactive and important elements.
- White text for titles, light gray for secondary text.
- Exact visual details come from the image. The values below are a **starting point** to tune against it:

| Token | Starting value |
|---|---|
| `background` | about `#1C1F26` |
| `surface` (cards, fields) | about `#22262E` |
| `text-primary` | `#FFFFFF` |
| `text-secondary` | `#9AA0AA` |
| `accent` (default) | the red in the image (about `#E8505B`) |
| `radius-large` | 20-28px (bubbles, fields, bottom bar) |
| `radius-round` | fully circular (icon buttons, avatars) |
| `shadow-raised` | dark shadow bottom-right + light shadow top-left |
| `shadow-inset` | the inverse (for sunken fields such as search) |

### 4.2 Chat list screen (left side of the image)
- **Header:** small user avatar (left), bold **Chats** title, and a round accent-colored **+** button (right) for starting a chat or refreshing people.
- **Search field:** inset, rounded, faint placeholder text.
- **Person row:**
  - Round avatar with a soft ring.
  - Bold name, and below it the last message in small gray text (single line, truncated).
  - Right side: **time** (accent color if there are unread messages, gray otherwise) and below it an **unread badge** (accent pill; the count caps at `99+`).
  - **Visibility toggle** (eye icon): on the People page in 1.1.3; when off, the person must look clearly different (crossed-out eye, muted color).
  - Very thin dividers between rows.
  - Online/offline: a small dot on the avatar.
- **Bottom bar:** a floating pill with round raised icon buttons: **Chats** (active, accent color), **Account** (security, profile, app lock), **Settings** (habits, appearance, people, notifications, updates, about, danger), **Camera** (take a photo and send it, scan a Kinly QR code, OCR text). The pill animates the active icon with a scale + fade that respects the reduce-motion setting.

### 4.3 Chat screen (right side of the image)
- **Header:** round back button (accent arrow), avatar, name, and below it **"Typing..."** while the peer types (otherwise "online" / "last seen"), and round voice/video call buttons (accent phone/video icons). Visibility lives on the People page, not in the chat header.
- **Date separator:** small centered text ("Today").
- **Bubbles:**
  - Received: dark raised surface, white text.
  - Sent: **accent color**, text white or black depending on contrast, rounded corners.
  - Time shown inside the bubble in small text.
  - Sent-message states: sending -> sent -> delivered -> read -> failed (with retry).
- **Input bar:** an inset rounded field with an emoji icon (left), placeholder, attachment (paperclip) and camera icons; next to it a **large round accent microphone button** that turns into a send button when text is present.
- **Files:** a file bubble with a progress bar, speed and percentage, plus cancel/resume.

### 4.4 Accent color customization (required)
- **Settings -> Appearance:** preset palette + free color picker + **live preview** of a list row and bubbles.
- One color drives: sent bubbles, unread badges, unread times, the + / call / mic / back buttons, the active tab, and the glow around active buttons.
- Neumorphic shadows stay neutral (not tinted); only a light accent glow is used on active elements.
- **Contrast guards:**
  - Text color on the accent is chosen automatically (white or black) from the color's luminance, with a contrast ratio of at least 4.5:1.
  - Block or warn on colors too close to the background color.
- The color is **stored locally** on the device and is never sent to other users.
- Optional later: extra themes (light, glass) built from the same tokens.

### 4.5 Animation
- Bubble entrance (light fade/slide), badge changes, button press (slight sink for neumorphism), screen transitions.
- Animation must serve a purpose. Add a **"Reduce motion"** setting.

### 4.6 Language and direction
- Arabic and English with **full RTL** (mirror the layout, not just the text). Message bubble text direction follows the language of the text.

### 4.7 Welcome screen
- Same style. Name field with **live uniqueness check**, optional photo, and an "Enter" button.

### 4.8 Call screen
- Voice: large avatar + timer + buttons (mute, speaker, end).
- Video (Android): the peer's video full screen + a small self-preview + buttons (mute, camera off, flip camera, end).

### 4.9 Settings
- Name and photo, **Appearance (accent color)**, language, Security (device fingerprint, app lock, hidden list), notifications, reduce motion, About/version.

---

## 5. Technical architecture

### 5.1 Repository layout (monorepo)
```
core/                 Rust core (protocol, crypto, discovery, storage, files) + tests
app/                  Flutter app (android + linux); all UI lives here
  android/            Kotlin system glue (foreground service, Bluetooth, MulticastLock)
docs/                 protocol spec and design decisions
.github/workflows/    ci.yml and release.yml
PLAN.md
ui-reference.png
```
- Flutter <-> Rust binding via `flutter_rust_bridge` (or equivalent).
- All business logic lives in the core. The UI only displays state and sends commands.

### 5.2 Identity
- Each device generates an **identity key** (Ed25519) on first run and stores it securely (Android Keystore / a restricted-permission file on Arch).
- The real identity is the public key. The name is only a display label.

### 5.3 Discovery
- **mDNS** (a service such as `_kinly._tcp`).
- The broadcast beacon is **anonymous**: a random rotating ID + port, **no name**.
- The name is only sent after a successful **encrypted handshake** (see section 6).

### 5.4 Transport
- A `Transport` abstraction with two implementations: **TCP** (Wi-Fi/hotspot) and **Bluetooth RFCOMM** (fallback). The same encrypted protocol runs on both.
- Length-prefixed frames with a structured payload.
- Message types: `HELLO(name, avatar)`, `MSG`, `ACK(state)`, `TYPING`, `FILE_OFFER`, `FILE_ACCEPT`, `FILE_CHUNK`, `FILE_CANCEL`, `CALL_SIGNAL`, `VISIBILITY`, `PRESENCE`.

### 5.5 Encryption
- **Noise Protocol** (pattern `Noise_XX`) via an established library (for example `snow`). X25519 + ChaCha20-Poly1305.
- **Do not invent a cryptographic protocol.** Use well-known libraries only.
- Ephemeral keys per session (forward secrecy).
- The local database is encrypted (SQLCipher or equivalent).
- The key fingerprint is shown in each chat's settings, and can be verified by scanning a QR code (Scan button).

### 5.6 Files
- Chunks of 256KB-1MB inside the same encrypted channel.
- Integrity check with a hash (for example BLAKE3).
- Progress bar and speed, and **resume** after a connection drop.
- Goal: throughput close to the actual network speed.

### 5.7 Calls (Android)
- **WebRTC** (`flutter_webrtc` or libwebrtc directly).
- No STUN/TURN: ICE with local-network candidates only.
- Signaling (SDP/ICE) goes through the encrypted channel.
- Phase one is voice, then video.

### 5.7.1 Calls in 1.1.3

- Basic voice and video calls ship in **1.1.3** (video on Android only).
- Call legs: outgoing offer / incoming answer / hangup, ICE candidates, ring
  timeout (~30s), busy/offline handling, mute and camera toggles, speaker
  routing and local/remote preview.
- The **app lock** gates the call screen the same way it gates the app.
- Background and locked-screen calls are deferred to **1.1.4**.

### 5.8 Bluetooth (fallback)
- Bluetooth Classic RFCOMM carrying the same message protocol.
- Supported: messages and small files. Enforce a file-size limit with a clear warning.
- **No calls.**
- The UI first suggests "turn on a hotspot" before relying on Bluetooth.

### 5.9 Storage
- Encrypted SQLite: people, conversations, messages, file transfers, hidden list, appearance settings.
- An outgoing queue for messages addressed to offline peers.

---

## 6. Hiding (visibility toggle)

- Every person has a visibility toggle (**ON by default**).
- If the user turns it off for Mohamed:
  1. The user's device **ignores Mohamed's handshake**, so the user's name never reaches him.
  2. The user's device sends him `VISIBILITY=hidden`, and Mohamed's app **hides the user's name and the whole conversation**.
  3. Old messages stay stored (encrypted) and reappear when the toggle is turned on again.
- Hiding is **one-directional**: the user still sees Mohamed even if Mohamed is hidden from the user.
- If the user starts a conversation with Mohamed while hidden from him, the toggle for him is turned on automatically (otherwise he could not reply).
- **Known limit:** hiding old conversation history depends on Mohamed's app honoring the command. Acceptable for family use.

## 7. Unique names

- A name is bound to a device key.
- On entry: if the name is already used by a visible or known device with a different key -> **reject** with a "name already taken" message.
- Edge case: two devices that never met pick the same name -> on first contact, the **newer** one is asked to rename.

## 8. Platform notes

### Android
- A **foreground service** receives messages while the app is in the background, with a persistent quiet notification (minimum importance, no sound, no vibration, no badge, no timestamp).
- A persisted **"Receive messages in background"** setting (default on) turns the service on or off; when off, messages arrive only while the app is open.
- A persisted **app lock** (biometric with the device-credential/PIN fallback) gates the app on launch and resume.
- Permissions (requested when needed): local network / nearby devices, Bluetooth, notifications, camera, microphone; `minSdk 28` so Android 9 through 16+ are supported.
- A `MulticastLock` so mDNS works.
- Guide the user to exempt the app from battery optimization.

### Arch Linux
- Same core and protocol, Flutter UI.
- Open the app's TCP port and UDP 5353 (mDNS) in the firewall (document the commands).
- No video. Voice calls are optional and late.

---

## 9. Build and release (GitHub Actions)

### 9.1 Idea
All building happens on GitHub's servers. The agent pushes code to the owner's repository; Actions test, build, and upload the results to the **Releases** page of the same repository.

### 9.2 Workflows

**`ci.yml`** (on every push and pull request):
- Rust: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test` (core).
- Flutter: `flutter analyze`, `flutter test`.
- Fail the run if any step fails.

**`release.yml`** (on a tag like `vX.Y.Z`):
1. **Android:**
   - Set up Java and Android SDK/NDK (pinned versions) and Rust with targets: `aarch64-linux-android` (primary), `armv7-linux-androideabi` and `x86_64-linux-android` (optional).
   - Build the Rust core per target (for example with `cargo-ndk`).
   - Build `flutter build apk --release` (optionally `--split-per-abi`).
   - **Sign the APK** with the key from Secrets (see 9.3).
2. **Linux (Arch):**
   - Build inside an `archlinux:latest` container to guarantee library compatibility.
   - Output: a `tar.gz` of the app + a `sha256` file (a `PKGBUILD` can come later).
3. **Publish:** create a **GitHub Release** named after the tag and upload all files as assets (for example with `softprops/action-gh-release`).
4. Also upload the APK as a workflow **artifact** for backup.

### 9.3 Required secrets (set in the repository settings)
- `ANDROID_KEYSTORE_BASE64`: the keystore file, base64-encoded.
- `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
- **Never** commit the keystore or passwords.

### 9.4 Signing and versions
- **The signing key is generated once** and backed up by the owner outside GitHub. **If it is lost, the app cannot be updated on devices that already have it installed (it must be uninstalled and reinstalled).**
- `versionName` comes from the tag; `versionCode` comes from the build number in `app/pubspec.yaml` (for example `1.1.3+4` -> version name `1.1.3`, build number `4`).
- The resulting APK is installed manually on family devices (allow installs from unknown sources).

### 9.7 1.1.3 release state
- Release name: **1.1.3** (build `1.1.3+4`).
- CI signs every build with the stable release keystore from GitHub Secrets (`apk.yml` and `release.yml` both decode it and fail fast when missing; the keystore is kept outside the repository).
- The rolling test pre-release is `apk-1.1.3` (arm64, signed with the stable key); the final release is `v1.1.3`.
- Basic voice/video calls ship in 1.1.3; background and locked-screen calls are deferred to 1.1.4.

### 9.5 Repository and workflow
- A **private** repository under the owner's account (name to be set). On private repos the free Actions minutes are limited by the account plan, so watch consumption (cache Rust and Flutter dependencies).
- Branches: `main` is stable; the agent works on branches and opens PRs; CI must pass before merging.
- Each phase ends with a release tag (for example `v0.1.0` after phase 1).

### 9.6 Limits of server-side testing
CI will **not** test: real device-to-device networking, Bluetooth, calls, notifications, or background behavior. Those are covered by the **owner testing on real devices** using the APK uploaded to Releases.

---

## 10. Phases and acceptance criteria

Every phase ends with: code merged into `main` + green CI + a release tag + a real-device test checklist (where needed).

**Phase 0 - Setup**
- Repository layout, working `ci.yml`, an empty Flutter project that builds, signs and uploads a test APK to a Release.
- Accept: `v0.0.1` contains an APK that installs and opens.

**Phase 1 - Core + CLI on Arch**
- Discovery, encrypted handshake, messages, files, hiding, unique names.
- Accept: two processes (or devices) see each other and exchange messages.
- Accept: a packet capture shows **no plaintext**.
- Accept: a file of at least 1GB transfers without corruption (matching hash) and resumes after an interruption.
- Accept: turning the visibility toggle off hides the name and conversation on the other side.
- Accept: a duplicate name is rejected.
- Accept: core tests cover crypto, hiding, names and file transfer.

**Phase 2 - Android UI (primary)**
- Welcome screen, chat list, chat screen, file transfer, visibility toggle, settings.
- Accept: visual match with the reference design (`ui-reference.png`).
- Accept: changing and persisting the accent color works, and contrast guards work.
- Accept: RTL and Arabic/English are correct.
- Accept: receiving messages in the background (foreground service).
- Accept: tested on two real Android devices.

**Phase 3 - Android calls**
- Voice first, then video.
- Accept: voice and video calls between two devices on Wi-Fi/hotspot **with no internet**.

**Phase 4 - Arch UI**
- Chat, files and hiding with the same Flutter UI.
- Accept: messages and files exchanged between Arch and Android.
- Accept: the Linux build is uploaded to the Release.

**Phase 5 - Bluetooth fallback**
- Accept: messages and small files between two devices without Wi-Fi.

---

## 11. Known risks

- Some routers isolate devices (AP isolation) -> use a hotspot.
- Android kills background services -> foreground service and battery-optimization exemption.
- Bluetooth is slow and limited -> fallback only.
- WebRTC is the hardest part -> start with voice and test on real devices.
- Dark neumorphism is contrast-sensitive -> the contrast guards in 4.4.
- Hiding relies on the other app honoring it (acceptable for family).
- Losing the keystore -> keep a backup (9.4).
- Rust + Flutter builds on Actions are slow and use minutes -> use caching.

## 12. Out of scope (for now)

- Play Store, groups, iOS, a central server.
- Video on Arch.
- The camera tab (deferred).

## 13. Instructions for the agent

- Read `ui-reference.png` before any UI work.
- Follow the phases in order. Do not start a phase before the previous phase's acceptance criteria are met.
- Use established crypto libraries only.
- Write tests for the core (crypto, hiding, names, file transfer).
- Never commit secrets or the keystore.
- If an open decision (section 2) affects your work, **ask** instead of assuming.
- Small commits with clear messages, and a PR per phase (or part of one).
- At the end of each phase, write a short summary: what was done, what needs manual testing on real devices, and any problems.
