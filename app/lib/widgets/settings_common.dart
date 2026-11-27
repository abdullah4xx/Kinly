import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../state/node_controller.dart';
import '../theme/neu.dart';
import '../theme/tokens.dart';
import '../util/avatar_picker.dart';
import '../widgets/avatar.dart';

/// Page chrome shared by every settings subpage. Standalone pages get a back
/// button; the embedded dock tab relies on the dock itself.
class SettingsPageBody extends StatelessWidget {
  const SettingsPageBody({
    super.key,
    required this.title,
    required this.children,
    this.embedded = false,
    this.header,
  });

  final String title;
  final List<Widget> children;
  final bool embedded;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsetsDirectional.fromSTEB(
          20,
          embedded ? 16 : 12,
          20,
          embedded ? 120 : 32,
        ),
        children: [
          Row(
            children: [
              if (!embedded) ...[
                NeuIconButton(
                  icon: Icons.arrow_back_rounded,
                  accent: true,
                  size: 44,
                  iconSize: 20,
                  tooltip: strings.get('close'),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: embedded ? 24 : 22,
                    fontWeight: FontWeight.w800,
                    color: Tokens.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (header != null) ...[header!, const SizedBox(height: 20)],
          ...children,
        ],
      ),
    );
  }
}

class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Tokens.textSecondary,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
  }
}

class SettingsLinkRow extends StatelessWidget {
  const SettingsLinkRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle = '',
    this.danger = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: danger ? Tokens.danger : Tokens.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: danger ? Tokens.danger : Tokens.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Tokens.textMuted,
                        fontSize: 10.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Tokens.textMuted,
                ),
          ],
        ),
      ),
    );
  }
}

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 19, color: Tokens.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Tokens.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Tokens.textMuted,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            NeuToggle(
              value: value,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsChoice extends StatelessWidget {
  const SettingsChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Neu(
        inset: selected,
        accent: selected,
        radius: Tokens.radiusMedium,
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? readableOn(accent) : Tokens.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Profile photo + name, used by the settings hub and the account page.
class ProfileSummaryCard extends StatelessWidget {
  const ProfileSummaryCard({
    super.key,
    required this.controller,
    required this.onChangeName,
    required this.onChangePhoto,
    required this.onRemovePhoto,
  });

  final NodeController controller;
  final VoidCallback onChangeName;
  final VoidCallback onChangePhoto;
  final VoidCallback onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    return Neu(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: onChangePhoto,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                KinlyAvatar(
                  name: controller.name,
                  avatarBase64: controller.avatarBase64,
                  size: 62,
                  showDot: false,
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Tokens.surfaceHigh,
                      border: Border.all(color: Tokens.background, width: 2),
                    ),
                    child: Icon(
                      Icons.edit_rounded,
                      size: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Tokens.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  strings.get('profile'),
                  style: const TextStyle(
                    color: Tokens.textMuted,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    GestureDetector(
                      onTap: onChangeName,
                      child: Text(
                        strings.get('changeName'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (controller.avatarBase64 != null) ...[
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: onRemovePhoto,
                        child: Text(
                          strings.get('removePhoto'),
                          style: const TextStyle(
                            color: Tokens.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool danger = true,
}) async {
  final strings = StringsScope.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Tokens.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusLarge),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Tokens.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        body,
        style: const TextStyle(
          color: Tokens.textSecondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            strings.get('cancel'),
            style: const TextStyle(color: Tokens.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            action,
            style: TextStyle(
              color: danger ? Tokens.danger : Tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for a new name and saves it through the controller.
Future<void> editProfileName(
  BuildContext context,
  NodeController controller,
) async {
  final strings = StringsScope.of(context);
  final field = TextEditingController(text: controller.name);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Tokens.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusLarge),
      ),
      title: Text(
        strings.get('changeName'),
        style: const TextStyle(color: Tokens.textPrimary, fontSize: 17),
      ),
      content: TextField(
        controller: field,
        autofocus: true,
        maxLength: 32,
        style: const TextStyle(color: Tokens.textPrimary),
        decoration: InputDecoration(
          counterText: '',
          hintText: strings.get('nameHint'),
          hintStyle: const TextStyle(color: Tokens.textMuted),
        ),
        onSubmitted: (text) => Navigator.of(context).pop(text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            strings.get('cancel'),
            style: const TextStyle(color: Tokens.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(field.text),
          child: Text(
            strings.get('save'),
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ],
    ),
  );
  field.dispose();
  final name = value?.trim() ?? '';
  if (name.isEmpty || name == controller.name) return;
  try {
    await controller.updateProfile(name: name);
  } catch (error) {
    if (!context.mounted) return;
    final message = error.toString().contains('already taken')
        ? strings.get('nameTakenLong')
        : strings.get('saveFailed');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

/// Picks a photo from the gallery and saves it as the profile photo.
Future<void> editProfilePhoto(
  BuildContext context,
  NodeController controller,
) async {
  final avatar = await pickAvatarBase64();
  if (avatar == null) return;
  try {
    await controller.updateProfile(avatarBase64: avatar);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(StringsScope.of(context).get('saveFailed'))),
    );
  }
}
