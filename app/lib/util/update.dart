import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../version.dart';

/// A newer build found on GitHub Releases.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.pageUrl,
    required this.notes,
    required this.assetName,
  });

  final String version;
  final String downloadUrl;
  final String pageUrl;
  final String notes;
  final String assetName;
}

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Asks GitHub for the newest release that ships an Android APK.
///
/// Returns null when the installed version is already the newest one.
/// Throws [UpdateException] when GitHub cannot be reached or the response is
/// not usable, so the caller can show a retryable message.
Future<UpdateInfo?> checkForUpdate({
  String currentVersion = appVersion,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client
        .getUrl(Uri.parse(releasesApiUrl))
        .timeout(timeout);
    request.headers.set(HttpHeaders.userAgentHeader, 'Kinly/$currentVersion');
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw UpdateException('GitHub replied ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    final releases = jsonDecode(body);
    if (releases is! List) {
      throw const UpdateException('Unexpected GitHub response');
    }
    UpdateInfo? newest;
    for (final entry in releases) {
      if (entry is! Map<String, dynamic>) continue;
      if (entry['draft'] == true) continue;
      final version = versionFromTag('${entry['tag_name'] ?? ''}');
      if (version == null) continue;
      final assets = entry['assets'];
      if (assets is! List) continue;
      Map<String, dynamic>? apk;
      for (final asset in assets) {
        if (asset is! Map<String, dynamic>) continue;
        final name = '${asset['name'] ?? ''}';
        if (!name.toLowerCase().endsWith('.apk')) continue;
        apk = asset;
        break;
      }
      if (apk == null) continue;
      final downloadUrl = '${apk['browser_download_url'] ?? ''}';
      if (downloadUrl.isEmpty) continue;
      if (newest != null && !isNewerVersion(version, newest.version)) continue;
      newest = UpdateInfo(
        version: version,
        downloadUrl: downloadUrl,
        pageUrl: '${entry['html_url'] ?? releasesPageUrl}',
        notes: '${entry['body'] ?? ''}'.trim(),
        assetName: '${apk['name'] ?? ''}',
      );
    }
    if (newest == null) return null;
    return isNewerVersion(newest.version, currentVersion) ? newest : null;
  } on TimeoutException {
    throw const UpdateException('GitHub took too long to answer');
  } on SocketException catch (error) {
    throw UpdateException(error.message);
  } on FormatException {
    throw const UpdateException('Unexpected GitHub response');
  } finally {
    client.close(force: true);
  }
}

/// Pulls `1.2.3` out of tags like `v1.2.3`, `apk-1.2.3` or `release/1.2.3`.
String? versionFromTag(String tag) {
  final match = RegExp(r'(\d+(?:\.\d+){0,3})').firstMatch(tag);
  return match?.group(1);
}

List<int> _parts(String version) {
  final parts = version.split('.').map(int.tryParse).toList();
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts.map((part) => part ?? 0).toList();
}

/// True when [candidate] is strictly newer than [current].
bool isNewerVersion(String candidate, String current) {
  final a = _parts(candidate);
  final b = _parts(current);
  for (var index = 0; index < 3; index++) {
    if (a[index] != b[index]) return a[index] > b[index];
  }
  return false;
}
