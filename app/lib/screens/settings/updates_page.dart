import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/node_controller.dart';
import '../../theme/neu.dart';
import '../../theme/tokens.dart';
import '../../util/system.dart';
import '../../util/update.dart';
import '../../version.dart';
import '../../widgets/settings_common.dart';

enum _Stage {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,
  ready,
  installing,
  error,
}

/// Checks GitHub, downloads the APK with progress and installs it in place.
class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key, required this.controller});

  final NodeController controller;

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  _Stage _stage = _Stage.idle;
  UpdateInfo? _update;
  String? _error;
  String? _apkPath;
  int _received = 0;
  int _total = 0;
  UpdateDownloader? _downloader;

  @override
  void dispose() {
    _downloader?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_stage == _Stage.checking || _stage == _Stage.downloading) return;
    final strings = StringsScope.of(context);
    setState(() {
      _stage = _Stage.checking;
      _error = null;
      _update = null;
      _apkPath = null;
      _received = 0;
      _total = 0;
    });
    try {
      final update = await checkForUpdate();
      if (!mounted) return;
      setState(() {
        _update = update;
        _stage = update == null ? _Stage.upToDate : _Stage.available;
      });
    } on UpdateException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '${strings.get('updateFailed')}: ${error.message}';
        _stage = _Stage.error;
      });
    }
  }

  Future<void> _download() async {
    final update = _update;
    if (update == null) return;
    final strings = StringsScope.of(context);
    final downloader = UpdateDownloader(
      update,
      onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _received = received;
          _total = total;
          if (total > 0 && received >= total) {
            _stage = _Stage.verifying;
          } else if (_stage != _Stage.verifying) {
            _stage = _Stage.downloading;
          }
        });
      },
    );
    _downloader = downloader;
    setState(() {
      _stage = _Stage.downloading;
      _received = 0;
      _total = update.size;
      _error = null;
    });
    try {
      final path = await downloader.download();
      if (!mounted) return;
      setState(() {
        _apkPath = path;
        _stage = _Stage.ready;
      });
    } on UpdateException catch (error) {
      if (!mounted) return;
      final cancelled = error.message.contains('cancel');
      setState(() {
        _error = cancelled
            ? null
            : '${strings.get('downloadFailed')}: ${error.message}';
        _stage = cancelled ? _Stage.available : _Stage.error;
      });
    } finally {
      _downloader = null;
    }
  }

  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return;
    final strings = StringsScope.of(context);
    setState(() => _stage = _Stage.installing);
    try {
      final allowed = await canInstallPackages();
      if (!allowed) {
        if (!mounted) return;
        setState(() {
          _error = strings.get('installPermission');
          _stage = _Stage.error;
        });
        return;
      }
      await installApk(path);
      if (!mounted) return;
      setState(() => _stage = _Stage.ready);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '${strings.get('installUpdate')}: $error';
        _stage = _Stage.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final update = _update;
    return SettingsPageBody(
      title: strings.get('updates'),
      children: [
        Neu(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Neu(
                width: 44,
                height: 44,
                radius: 14,
                accent: true,
                child: Icon(
                  Icons.system_update_alt_rounded,
                  size: 21,
                  color: readableOn(accent),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${strings.get('currentVersion')} $appVersion',
                      style: const TextStyle(
                        color: Tokens.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      Platform.isAndroid
                          ? strings.get('updatesBody')
                          : strings.get('updatesBody'),
                      style: const TextStyle(
                        color: Tokens.textMuted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (update != null) ...[
          Neu(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${strings.get('latestVersion')} ${update.version}',
                        style: const TextStyle(
                          color: Tokens.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (update.prerelease)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: withOpacity(accent, 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'pre-release',
                          style: TextStyle(
                            color: accent,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                if (update.notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    strings.get('releaseNotes'),
                    style: const TextStyle(
                      color: Tokens.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 190),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        update.notes,
                        style: const TextStyle(
                          color: Tokens.textMuted,
                          fontSize: 11.5,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_stage == _Stage.downloading || _stage == _Stage.verifying) ...[
          Neu(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _stage == _Stage.verifying
                            ? strings.get('verifying')
                            : strings.get('downloading'),
                        style: const TextStyle(
                          color: Tokens.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_total > 0)
                      Text(
                        '${(_received / _total * 100).clamp(0, 100).round()}%',
                        style: const TextStyle(
                          color: Tokens.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _stage == _Stage.verifying
                        ? null
                        : _total > 0
                        ? (_received / _total).clamp(0, 1)
                        : null,
                    minHeight: 6,
                    backgroundColor: withOpacity(Colors.white, 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    _downloader?.cancel();
                  },
                  child: Text(
                    strings.get('cancelDownload'),
                    style: TextStyle(
                      color: accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_error != null) ...[
          Text(
            _error!,
            style: const TextStyle(
              color: Tokens.danger,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_stage == _Stage.upToDate)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 17,
                  color: Tokens.success,
                ),
                const SizedBox(width: 8),
                Text(
                  strings.get('upToDate'),
                  style: const TextStyle(
                    color: Tokens.success,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            if (_stage == _Stage.available)
              AccentButton(
                label: strings.get('download'),
                icon: Icons.download_rounded,
                onPressed: _download,
              ),
            if (_stage == _Stage.ready)
              AccentButton(
                label: strings.get('installUpdate'),
                icon: Icons.install_mobile_rounded,
                onPressed: _install,
              ),
            if (_stage == _Stage.installing)
              AccentButton(
                label: strings.get('installing'),
                icon: Icons.install_mobile_rounded,
                onPressed: null,
              ),
            if (_stage == _Stage.idle ||
                _stage == _Stage.error ||
                _stage == _Stage.upToDate)
              AccentButton(
                label: strings.get('checkUpdates'),
                icon: Icons.refresh_rounded,
                onPressed: _check,
              ),
            if (_stage == _Stage.checking)
              AccentButton(
                label: strings.get('checkingUpdates'),
                icon: Icons.hourglass_top_rounded,
                onPressed: null,
              ),
          ],
        ),
        if (!Platform.isAndroid) ...[
          const SizedBox(height: 12),
          SettingsLinkRow(
            icon: Icons.open_in_new_rounded,
            title: strings.get('updates'),
            subtitle: releasesPageUrl,
            onTap: () => openUrl(releasesPageUrl),
          ),
        ],
      ],
    );
  }
}
