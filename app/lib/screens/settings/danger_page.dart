import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/node_controller.dart';
import '../../theme/neu.dart';
import '../../theme/tokens.dart';
import '../../widgets/settings_common.dart';
import '../welcome.dart';

/// Destructive actions: erase this device identity or quit on desktop.
class DangerPage extends StatelessWidget {
  const DangerPage({super.key, required this.controller});

  final NodeController controller;

  Future<void> _deleteIdentity(BuildContext context) async {
    final strings = StringsScope.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: strings.get('deleteConfirmTitle'),
      body: strings.get('deleteIdentityBody'),
      action: strings.get('delete'),
    );
    if (!confirmed || !context.mounted) return;
    final navigator = Navigator.of(context);
    final dataDir = controller.dataDir;
    await controller.wipe();
    if (!context.mounted) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => WelcomeScreen(
          controller: controller,
          dataDir: dataDir,
          onEntered: () => navigator.pop(),
        ),
      ),
    );
  }

  Future<void> _quit(BuildContext context) async {
    final strings = StringsScope.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: strings.get('quitConfirmTitle'),
      body: strings.get('quitBody'),
      action: strings.get('quit'),
      danger: false,
    );
    if (!confirmed) return;
    await controller.shutdown();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    return SettingsPageBody(
      title: strings.get('danger'),
      children: [
        Neu(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SettingsLinkRow(
                icon: Icons.delete_outline_rounded,
                title: strings.get('deleteIdentity'),
                subtitle: strings.get('deleteIdentityBody'),
                danger: true,
                onTap: () => _deleteIdentity(context),
              ),
              if (Platform.isLinux) ...[
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 58,
                  color: withOpacity(Colors.white, 0.04),
                ),
                SettingsLinkRow(
                  icon: Icons.logout_rounded,
                  title: strings.get('quit'),
                  subtitle: strings.get('quitBody'),
                  onTap: () => _quit(context),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          strings.get('deleteIdentityBody'),
          style: const TextStyle(
            color: Tokens.textMuted,
            fontSize: 11.5,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
