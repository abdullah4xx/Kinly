/// The app version shown in the UI and compared with GitHub releases.
///
/// Keep this in sync with `version:` in `pubspec.yaml`; a test checks it.
const String appVersion = '1.0.2';

/// Owner repository that publishes the Android builds.
const String githubRepo = 'abdullah4xx/Kinly';

/// GitHub API used by the in-app update check.
const String releasesApiUrl =
    'https://api.github.com/repos/$githubRepo/releases';

/// Public page with every release, used when no APK asset is found.
const String releasesPageUrl = 'https://github.com/$githubRepo/releases';
