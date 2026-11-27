import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/node_controller.dart';
import '../../theme/neu.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../../widgets/avatar.dart';
import '../../widgets/settings_common.dart';

/// Every person on the network, with the one-directional visibility switch.
/// This is the only place the switch lives; the chat list stays clean.
class PeoplePage extends StatelessWidget {
  const PeoplePage({super.key, required this.controller});

  final NodeController controller;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final people = [...controller.people];
        people.sort((a, b) {
          final selfA = controller.isSelf(a.deviceId);
          final selfB = controller.isSelf(b.deviceId);
          if (selfA != selfB) return selfA ? -1 : 1;
          if (a.online != b.online) return a.online ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return SettingsPageBody(
          title: strings.get('people'),
          children: [
            Text(
              strings.get('peopleBody'),
              style: const TextStyle(
                color: Tokens.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            if (people.isEmpty)
              Neu(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 22,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.people_outline_rounded,
                      color: Tokens.textMuted,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        strings.get('noPeopleBody'),
                        style: const TextStyle(
                          color: Tokens.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Neu(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (var index = 0; index < people.length; index++) ...[
                      if (index > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          indent: 70,
                          endIndent: 14,
                          color: withOpacity(Colors.white, 0.035),
                        ),
                      _PersonRow(
                        controller: controller,
                        person: people[index],
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(
                  Icons.visibility_off_outlined,
                  size: 15,
                  color: Tokens.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.get('hideHint'),
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
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.controller, required this.person});

  final NodeController controller;
  final PersonInfo person;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final isSelf = controller.isSelf(person.deviceId);
    final hidden = !person.visible && !isSelf;
    final typing = controller.isTyping(person.deviceId);

    final String status;
    if (isSelf) {
      status = strings.get('onlyOnThisDevice');
    } else if (typing) {
      status = strings.get('typing');
    } else if (person.hiddenByPeer) {
      status = strings.get('hiddenFromYou');
    } else if (person.online) {
      status = strings.get('online');
    } else if (person.lastSeen > BigInt.zero) {
      status =
          '${strings.get('lastSeen')} '
          '${listTime(person.lastSeen.toInt(), strings.language)}';
    } else {
      status = strings.get('offline');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          KinlyAvatar(
            name: person.name,
            avatarBase64: person.avatar,
            online: person.online && !isSelf,
            size: 42,
            muted: hidden,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: person.name,
                    children: [
                      if (isSelf)
                        TextSpan(
                          text: ' (${strings.get('you')})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Tokens.textMuted,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hidden ? Tokens.textSecondary : Tokens.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Tokens.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (!isSelf) ...[
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                NeuToggle(
                  value: person.visible,
                  onChanged: (value) =>
                      controller.setVisibility(person.deviceId, value),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
