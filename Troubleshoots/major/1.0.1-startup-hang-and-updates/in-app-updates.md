# 05 — In-app update checks from GitHub Releases

**Type:** feature, not a defect.
**Status:** shipped in **1.0.1**.
**Entry point:** Settings → About → "Check for updates" (Android only).

## Behaviour

- Calls `https://api.github.com/repos/abdullah4xx/Kinly/releases` with
  `User-Agent: Kinly/<version>` and `Accept: application/vnd.github+json`.
- Parses every non-draft release, keeps the ones with an `.apk` asset, and
  extracts the version from tags such as `apk-1.0.1`, `v1.2.3`, or
  `release/2.0`.
- Compares numeric parts (`1.0.1 > 1.0.0`) and returns nothing when the
  installed build is current.
- When a newer build exists, shows a bilingual dialog with the release notes
  (truncated to 400 characters) and a Download button. Download opens the
  asset URL through the `app.kinly.chat/system` Android channel
  (`openUrl`), which launches the system browser.
- Network errors and timeouts (8 s connect, 15 s overall) surface a
  retryable "Update check failed: ..." line under the row.

## Files

- `app/lib/version.dart` — `appVersion`, repo, API and releases URLs.
- `app/lib/util/update.dart` — release parsing and version comparison.
- `app/lib/util/system.dart` — `openUrl` (Android channel; `xdg-open` on
  Linux).
- `app/android/.../MainActivity.kt` — `openUrl` handler with
  `Intent.ACTION_VIEW`.
- `app/lib/screens/settings.dart` — About row, checking state, dialog.
- `app/test/update_test.dart` — tag parsing, comparison, and a guard that
  `pubspec.yaml`'s version equals `appVersion`.

## Notes and limits

- GitHub allows 60 unauthenticated API calls per hour per IP; a manual
  button press is well inside that.
- Only APK assets are considered, so the Linux archive will need its own
  asset filter when desktop releases start shipping.
- The app does not download or install silently; Android requires the user
  to confirm the APK in the browser/package installer.
- Test builds are pre-releases (`apk-*` tags) and are still returned by the
  API, which is intentional for sideloaded testing.
