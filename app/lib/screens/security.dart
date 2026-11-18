import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/strings.dart';
import '../state/node_controller.dart';
import '../theme/neu.dart';
import '../theme/tokens.dart';
import '../widgets/avatar.dart';

/// Security tab: this device's fingerprint plus the shared safety code for
/// every known person. The same screen can be opened from a chat.
class SecurityScreen extends StatelessWidget {
  const SecurityScreen({
    super.key,
    required this.controller,
    this.embedded = true,
  });

  final NodeController controller;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final content = AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final people = controller.people
            .where((person) => !person.hiddenByPeer)
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return ListView(
          padding: EdgeInsets.fromLTRB(20, 8, 20, embedded ? 118 : 32),
          children: [
            if (!embedded) ...[
              Row(
                children: [
                  NeuIconButton(
                    icon: Icons.arrow_back_rounded,
                    accent: true,
                    size: 44,
                    iconSize: 20,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    strings.get('security'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Tokens.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
            ],
            _DeviceCard(controller: controller),
            const SizedBox(height: 26),
            Text(
              strings.get('verifyPerson'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Tokens.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 12),
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
                        strings.get('noPeopleToVerify'),
                        style: const TextStyle(
                          color: Tokens.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Neu(
                padding: const EdgeInsets.symmetric(vertical: 6),
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
                      _VerifyRow(
                        person: people[index],
                        onTap: () => showPeerSecurity(
                          context,
                          controller,
                          people[index],
                        ),
                      ),
                    ],
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

    if (!embedded) {
      return Scaffold(
        body: SafeArea(child: content),
      );
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                strings.get('security'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Tokens.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.controller});

  final NodeController controller;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final fingerprint = controller.fingerprint;

    return Neu(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Neu(
                width: 44,
                height: 44,
                radius: Tokens.radiusRound,
                accent: true,
                child: Icon(
                  Icons.shield_rounded,
                  size: 21,
                  color: readableOn(accent),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.get('thisDevice'),
                      style: const TextStyle(
                        color: Tokens.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      controller.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Tokens.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            strings.get('deviceFingerprint'),
            style: const TextStyle(
              color: Tokens.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Neu(
            inset: true,
            radius: Tokens.radiusMedium,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    fingerprint.isEmpty ? '—' : fingerprint,
                    style: const TextStyle(
                      color: Tokens.textPrimary,
                      fontSize: 13,
                      height: 1.5,
                      fontFamily: 'monospace',
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: fingerprint.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: fingerprint.replaceAll(' ', '')),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(strings.get('copied')),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                  child: const Icon(
                    Icons.copy_rounded,
                    size: 17,
                    color: Tokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifyRow extends StatelessWidget {
  const _VerifyRow({required this.person, required this.onTap});

  final PersonInfo person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            KinlyAvatar(
              name: person.name,
              avatarBase64: person.avatar,
              online: person.online,
              size: 42,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Tokens.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.qr_code_rounded,
              size: 19,
              color: Tokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet with the shared safety code and its QR.
Future<void> showPeerSecurity(
  BuildContext context,
  NodeController controller,
  PersonInfo person,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _PeerSecuritySheet(
      controller: controller,
      person: person,
    ),
  );
}

class _PeerSecuritySheet extends StatelessWidget {
  const _PeerSecuritySheet({required this.controller, required this.person});

  final NodeController controller;
  final PersonInfo person;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final code = controller.safetyCodeFor(person.deviceId);
    final digits = code.replaceAll(' ', '');
    final groups = code.isEmpty ? const <String>[] : code.split(' ');

    return Container(
      decoration: const BoxDecoration(
        color: Tokens.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Tokens.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 22),
              KinlyAvatar(
                name: person.name,
                avatarBase64: person.avatar,
                size: 64,
              ),
              const SizedBox(height: 12),
              Text(
                person.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Tokens.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                strings.get('sharedCode'),
                style: const TextStyle(
                  color: Tokens.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              if (code.isEmpty)
                Text(
                  strings.get('error'),
                  style: const TextStyle(color: Tokens.danger, fontSize: 13),
                )
              else ...[
                Neu(
                  inset: true,
                  radius: Tokens.radiusLarge,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Column(
                    children: [
                      for (var row = 0; row < 3; row++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              for (var column = 0; column < 4; column++)
                                Text(
                                  groups[row * 4 + column],
                                  style: const TextStyle(
                                    color: Tokens.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'monospace',
                                    letterSpacing: 1.2,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(Tokens.radiusMedium),
                  ),
                  child: QrImageView(
                    data: 'kinly://verify?device=${person.deviceId}&code=$digits',
                    size: 190,
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF1C1F26),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF1C1F26),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  strings.get('sharedCodeBody'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Tokens.textSecondary,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: AccentButton(
                        label: strings.get('copy'),
                        icon: Icons.copy_rounded,
                        expand: true,
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: digits));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(strings.get('codeCopied')),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    NeuIconButton(
                      icon: Icons.close_rounded,
                      size: 52,
                      iconSize: 20,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
