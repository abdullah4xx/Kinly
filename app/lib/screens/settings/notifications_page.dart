import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/node_controller.dart';
import '../../theme/neu.dart';
import '../../theme/tokens.dart';
import '../../util/system.dart';
import '../../widgets/settings_common.dart';

/// Background receiving and the silent foreground notification.
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key, required this.controller});

  final NodeController controller;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    return AnimatedBuilder(
      animation: controller.settings,
      builder: (context, _) {
        final settings = controller.settings;
        return SettingsPageBody(
          title: strings.get('notifications'),
          children: [
            Neu(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              child: SettingsToggleRow(
                icon: Icons.notifications_none_rounded,
                title: strings.get('backgroundReceive'),
                subtitle: strings.get('backgroundReceiveBody'),
                value: settings.backgroundReceive,
                onChanged: (value) async {
                  await settings.setBackgroundReceive(value);
                  await setBackgroundService(value);
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: Tokens.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.get('backgroundReceiveOff'),
                    style: const TextStyle(
                      color: Tokens.textMuted,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
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
