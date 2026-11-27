import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/neu.dart';
import '../../theme/tokens.dart';
import '../../util/system.dart';
import '../../version.dart';
import '../../widgets/settings_common.dart';

/// Version, source code and credits.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return SettingsPageBody(
      title: strings.get('about'),
      children: [
        Neu(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Neu(
                width: 72,
                height: 72,
                radius: Tokens.radiusRound,
                accent: true,
                child: Icon(
                  Icons.forum_rounded,
                  size: 32,
                  color: readableOn(accent),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                strings.get('appName'),
                style: const TextStyle(
                  color: Tokens.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${strings.get('version')} $appVersion',
                style: const TextStyle(
                  color: Tokens.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                strings.get('aboutBody'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Tokens.textSecondary,
                  fontSize: 12.5,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Neu(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              SettingsLinkRow(
                icon: Icons.code_rounded,
                title: 'GitHub',
                subtitle: 'https://github.com/$githubRepo',
                onTap: () => openUrl('https://github.com/$githubRepo'),
              ),
              Divider(
                height: 1,
                thickness: 1,
                indent: 58,
                color: withOpacity(Colors.white, 0.04),
              ),
              SettingsLinkRow(
                icon: Icons.favorite_outline_rounded,
                title: strings.get('madeBy'),
                subtitle: strings.get('tagline'),
                onTap: () {},
                trailing: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
