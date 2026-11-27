import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/node_controller.dart';
import '../../theme/neu.dart';
import '../../theme/tokens.dart';
import '../../widgets/settings_common.dart';
import 'about_page.dart';
import 'account_page.dart';
import 'appearance_page.dart';
import 'danger_page.dart';
import 'notifications_page.dart';
import 'people_page.dart';
import 'updates_page.dart';

/// The settings hub: a profile card and one row per focused page.
///
/// Kept as a tab in the bottom dock ([embedded] true) and reachable as a
/// standalone pushed page from the chat list header.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.embedded = true,
  });

  final NodeController controller;
  final bool embedded;

  void _open(BuildContext context, Widget page) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([controller, controller.settings]),
      builder: (context, _) {
        return SettingsPageBody(
          title: strings.get('settings'),
          embedded: embedded,
          header: ProfileSummaryCard(
            controller: controller,
            onChangeName: () => editProfileName(context, controller),
            onChangePhoto: () => editProfilePhoto(context, controller),
            onRemovePhoto: () => controller.updateProfile(removeAvatar: true),
          ),
          children: [
            Neu(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SettingsLinkRow(
                    icon: Icons.person_outline_rounded,
                    title: strings.get('account'),
                    subtitle: strings.get('accountBody'),
                    onTap: () =>
                        _open(context, AccountPage(controller: controller)),
                  ),
                  _divider(),
                  SettingsLinkRow(
                    icon: Icons.palette_outlined,
                    title: strings.get('appearance'),
                    subtitle: strings.get('appearanceBody'),
                    onTap: () =>
                        _open(context, AppearancePage(controller: controller)),
                  ),
                  _divider(),
                  SettingsLinkRow(
                    icon: Icons.people_outline_rounded,
                    title: strings.get('people'),
                    subtitle: strings.get('peopleBody'),
                    onTap: () =>
                        _open(context, PeoplePage(controller: controller)),
                  ),
                  _divider(),
                  SettingsLinkRow(
                    icon: Icons.notifications_none_rounded,
                    title: strings.get('notifications'),
                    subtitle: strings.get('notificationsBody'),
                    onTap: () => _open(
                      context,
                      NotificationsPage(controller: controller),
                    ),
                  ),
                  _divider(),
                  SettingsLinkRow(
                    icon: Icons.system_update_alt_rounded,
                    title: strings.get('updates'),
                    subtitle: strings.get('updatesBody'),
                    onTap: () =>
                        _open(context, UpdatesPage(controller: controller)),
                  ),
                  _divider(),
                  SettingsLinkRow(
                    icon: Icons.info_outline_rounded,
                    title: strings.get('about'),
                    subtitle: strings.get('aboutBodySettings'),
                    onTap: () => _open(context, const AboutPage()),
                  ),
                  _divider(),
                  SettingsLinkRow(
                    icon: Icons.warning_amber_rounded,
                    title: strings.get('danger'),
                    subtitle: strings.get('dangerBody'),
                    danger: true,
                    onTap: () => _open(
                      context,
                      DangerPage(controller: controller),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 15,
                  color: Tokens.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.get('fingerprintBody'),
                    style: const TextStyle(
                      color: Tokens.textMuted,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _divider() => Divider(
    height: 1,
    thickness: 1,
    indent: 58,
    color: withOpacity(Colors.white, 0.04),
  );
}
