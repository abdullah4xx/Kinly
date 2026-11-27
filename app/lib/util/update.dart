import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../version.dart';

/// A newer build found on GitHub Releases.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.pageUrl,
    required this.notes,
    required this.assetName,
    this.sha256Url = '',
    this.size = 0,
    this.prerelease = false,
  });

  final String version;
  final String downloadUrl;
  final String pageUrl;
  final String notes;
  final String assetName;

  /// Optional sidecar asset (`<apk>.sha256`) published by CI.
  final String sha256Url;
  final int size;
  final bool prerelease;

  bool get hasHash => sha256Url.isNotEmpty;
}

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Asks GitHub for the newest release that ships an Android APK.
///
/// Stable releases win over pre-releases, but a newer pre-release is still
/// offered when no stable release exists yet.
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
    UpdateInfo? stable;
    UpdateInfo? pre;
    for (final entry in releases) {
      if (entry is! Map<String, dynamic>) continue;
      if (entry['draft'] == true) continue;
      final version = versionFromTag('${entry['tag_name'] ?? ''}');
      if (version == null) continue;
      final assets = entry['assets'];
      if (assets is! List) continue;
      Map<String, dynamic>? apk;
      Map<String, dynamic>? hash;
      for (final asset in assets) {
        if (asset is! Map<String, dynamic>) continue;
        final name = '${asset['name'] ?? ''}'.toLowerCase();
        if (name.endsWith('.apk')) apk = asset;
        if (name.endsWith('.apk.sha256')) hash = asset;
      }
      if (apk == null) continue;
      final downloadUrl = '${apk['browser_download_url'] ?? ''}';
      if (downloadUrl.isEmpty) continue;
      final prerelease = entry['prerelease'] == true;
      final info = UpdateInfo(
        version: version,
        downloadUrl: downloadUrl,
        pageUrl: '${entry['html_url'] ?? releasesPageUrl}',
        notes: '${entry['body'] ?? ''}'.trim(),
        assetName: '${apk['name'] ?? ''}',
        sha256Url: '${hash?['browser_download_url'] ?? ''}',
        size: (apk['size'] as num?)?.toInt() ?? 0,
        prerelease: prerelease,
      );
      if (prerelease) {
        if (pre == null || isNewerVersion(version, pre.version)) pre = info;
      } else {
        if (stable == null || isNewerVersion(version, stable.version)) {
          stable = info;
        }
      }
    }
    final chosen = stable ?? pre;
    if (chosen == null) return null;
    return isNewerVersion(chosen.version, currentVersion) ? chosen : null;
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

/// Hosts the updater is allowed to talk to. Every redirect is re-checked.
const Set<String> updateHosts = {
  'github.com',
  'api.github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

/// Streams an APK with progress and verifies its SHA-256 before handing the
/// path to the system installer.
class UpdateDownloader {
  UpdateDownloader(this.info, {this.onProgress});

  final UpdateInfo info;
  final void Function(int received, int total)? onProgress;
  bool _cancelled = false;
  HttpClient? _client;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<String> download() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    _client = client;
    try {
      final response = await _open(client, Uri.parse(info.downloadUrl));
      final total = response.contentLength > 0
          ? response.contentLength
          : info.size;
      final directory = await getTemporaryDirectory();
      final folder = Directory('${directory.path}/updates');
      await folder.create(recursive: true);
      final file = File(
        '${folder.path}/kinly-${info.version}-${info.assetName}',
      );
      if (await file.exists()) await file.delete();
      final builder = BytesBuilder(copy: false);
      var received = 0;
      var lastReport = 0;
      await for (final chunk in response) {
        if (_cancelled) throw const UpdateException('Download cancelled');
        builder.add(chunk);
        received += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastReport > 160) {
          lastReport = now;
          onProgress?.call(received, total);
        }
      }
      onProgress?.call(received, total);
      if (total > 0 && received != total) {
        throw const UpdateException('Download is incomplete');
      }
      final bytes = builder.takeBytes();
      final digest = sha256.convert(bytes).toString();
      final expected = await _expectedHash(client);
      if (expected.isNotEmpty && digest != expected) {
        throw const UpdateException('SHA-256 mismatch');
      }
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } finally {
      client.close(force: true);
      _client = null;
    }
  }

  Future<String> _expectedHash(HttpClient client) async {
    if (!info.hasHash) return '';
    final response = await _open(client, Uri.parse(info.sha256Url));
    final body = await response.transform(utf8.decoder).join();
    final match = RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(body);
    return match?.group(0)?.toLowerCase() ?? '';
  }

  Future<HttpClientResponse> _open(HttpClient client, Uri uri) async {
    var current = uri;
    for (var hop = 0; hop < 6; hop++) {
      if (!_allowed(current)) {
        throw UpdateException('Refusing to download from ${current.host}');
      }
      final request = await client.getUrl(current);
      request.headers.set(HttpHeaders.userAgentHeader, 'Kinly/${info.version}');
      final response = await request.close();
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          throw const UpdateException('Redirect without a location');
        }
        await response.drain<void>();
        current = current.resolve(location);
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateException('Download failed with ${response.statusCode}');
      }
      return response;
    }
    throw const UpdateException('Too many redirects');
  }

  bool _allowed(Uri uri) =>
      uri.scheme == 'https' &&
      updateHosts.contains(uri.host.toLowerCase());
}
