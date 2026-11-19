# 01 — Bottom navigation floats in the middle of the screen

**Severity:** critical — it covers content on every screen that uses the dock
(Home and Settings).
**Status:** fixed in source (`app/lib/screens/home.dart`), not built into an
APK yet.
**Observed on:** 1.0.1+2, OPPO A38, Android 15, 720 x 1612 px @ 320 dpi.

## Symptoms

- The floating dock (chat / QR / settings) is drawn around `y = 747..837`
  instead of the bottom of the 1612 px screen.
- Everything below the dock is empty, while the dock sits on top of the page:
  - Home: it hides the inset Wi-Fi icon of the empty state and pushes the
    "No one here yet" copy below it.
  - Settings: it covers the accent swatches, the custom-colour row, and part
    of the language section.
- `extendBody: true` makes the body scroll underneath the misplaced bar, so
  the overlap looks like a rendering glitch rather than a layout slot.

Evidence:

- `../screenshots/01-home-english-dock-bug.png`
- `../screenshots/02-home-arabic-dock-bug.png`
- `../screenshots/03-settings-dock-overlap.png`
- `../screenshots/05-dock-overlap-detail.png` (close-up)

## Root cause

`Scaffold` measures `bottomNavigationBar` with loose constraints whose
`maxHeight` is the full screen height. The bar was wrapped in `Center` with
no `heightFactor`:

```dart
bottomNavigationBar: SafeArea(
  top: false,
  minimum: const EdgeInsets.only(bottom: 14),
  child: Center(
    child: Neu(/* the dock */),
  ),
),
```

`Center` expands to the maximum allowed height, so the bottom bar measured
**1612 px** tall. Scaffold then anchored that full-height bar to the bottom
of the screen, which put the dock itself exactly in the vertical middle.
`extendBody: true` let the body continue underneath it.

The same code would affect all Flutter versions; the dock is only visible
because the app now gets past the splash and the owner navigated the tabs.

## Fix

Shrink-wrap the centring widget to the dock height:

```dart
child: Center(
  heightFactor: 1,
  child: Neu(/* the dock */),
),
```

File: `app/lib/screens/home.dart`, inside `_HomeShellState.build`.

## Verification plan (after rebuilding)

1. Install the new APK over 1.0.1.
2. Open Home: the dock must sit at the bottom, below the empty state or the
   chat list; the Wi-Fi icon must be fully visible.
3. Open Settings and scroll to the end: the dock must not cover swatches,
   custom colour, language, security, hidden people, or About.
4. Check both English and Arabic; the dock order must stay mirrored in RTL
   (chat on the right, settings on the left).
5. Rotate/resize if the device supports it; the bar must stay anchored.
