import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/app_lock.dart';
import '../../state/node_controller.dart';
import '../../theme/neu.dart';
import '../../theme/tokens.dart';
import '../../util/system.dart';
import '../../widgets/settings_common.dart';
import '../security.dart';

/// Profile, language, security and the biometric app lock.
class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.controller,
    this.embedded = false,
  });

  final NodeController controller;
  final bool embedded;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  static const _lock = AppLockService();
  bool _busy = false;

  NodeController get _controller => widget.controller;

  Future<void> _toggleLock(bool enable) async {
    if (_busy) return;
    final strings = StringsScope.of(context);
    final settings = _controller.settings;
    setState(() => _busy = true);
    try {
      if (enable) {
        final can = await _lock.canAuthenticate();
        if (!can) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.get('noBiometrics'))),
          );
          return;
        }
        final ok = await _lock.authenticate(
          title: strings.get('appLockEnabled'),
          subtitle: strings.get('appLockSubtitle'),
        );
        if (!ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.get('lockFailed'))),
          );
          return;
        }
        await settings.setAppLock(true);
      } else {
        // Turning the lock off also asks for authentication, unless the
        // device has no usable authenticator.
        if (await _lock.canAuthenticate()) {
          final ok = await _lock.authenticate(
            title: strings.get('appLock'),
            subtitle: strings.get('appLockSubtitle'),
          );
          if (!ok) return;
        }
        await settings.setAppLock(false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _controller.settings]),
      builder: (context, _) {
        final settings = _controller.settings;
        return SettingsPageBody(
          title: strings.get('account'),
          embedded: widget.embedded,
          header: ProfileSummaryCard(
            controller: _controller,
            onChangeName: () => editProfileName(context, _controller),
            onChangePhoto: () => editProfilePhoto(context, _controller),
            onRemovePhoto: () =>
                _controller.updateProfile(removeAvatar: true),
          ),
          children: [
            SettingsSectionTitle(text: strings.get('language')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SettingsChoice(
                    label: strings.get('english'),
                    selected: settings.language == 'en',
                    onTap: () => settings.setLanguage('en'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SettingsChoice(
                    label: strings.get('arabic'),
                    selected: settings.language == 'ar',
                    onTap: () => settings.setLanguage('ar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            SettingsSectionTitle(text: strings.get('security')),
            const SizedBox(height: 10),
            Neu(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SettingsLinkRow(
                    icon: Icons.shield_outlined,
                    title: strings.get('fingerprint'),
                    subtitle: _controller.fingerprint.isEmpty
                        ? ''
                        : _controller.fingerprint,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SecurityScreen(
                          controller: _controller,
                          embedded: false,
                        ),
                      ),
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 58,
                    color: withOpacity(Colors.white, 0.04),
                  ),
                  SettingsToggleRow(
                    icon: Icons.fingerprint_rounded,
                    title: strings.get('appLock'),
                    subtitle: strings.get('appLockBody'),
                    value: settings.appLock,
                    enabled: !_busy && _lock.isSupported,
                    onChanged: _toggleLock,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (!_lock.isSupported)
              Text(
                strings.get('appLockUnavailable'),
                style: const TextStyle(
                  color: Tokens.textMuted,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              )
            else
              Text(
                strings.get('appLockBody'),
                style: const TextStyle(
                  color: Tokens.textMuted,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            if (supportsBatteryExemption) ...[
              const SizedBox(height: 26),
              SettingsSectionTitle(text: strings.get('batteryTitle')),
              const SizedBox(height: 10),
              Neu(
                padding: EdgeInsets.zero,
                child: SettingsLinkRow(
                  icon: Icons.battery_saver_rounded,
                  title: strings.get('batteryTitle'),
                  subtitle: strings.get('batteryBody'),
                  onTap: requestBatteryExemption,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
