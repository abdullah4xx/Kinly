import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../state/node_controller.dart';
import '../theme/neu.dart';
import '../theme/tokens.dart';
import '../util/avatar_picker.dart';
import '../util/system.dart';
import '../util/update.dart';
import '../version.dart';
import '../widgets/avatar.dart';
import 'security.dart';
import 'welcome.dart';

/// Profile, appearance, language, behaviour, security, hidden people and
/// destructive actions. Also reachable as a tab from the bottom bar.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.embedded = true,
  });

  final NodeController controller;
  final bool embedded;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  HSVColor? _custom;
  bool _customOpen = false;
  bool _checkingUpdate = false;
  String? _updateStatus;
  UpdateInfo? _update;

  NodeController get _controller => widget.controller;

  Future<void> _checkUpdates() async {
    if (_checkingUpdate) return;
    final strings = StringsScope.of(context);
    setState(() {
      _checkingUpdate = true;
      _updateStatus = null;
      _update = null;
    });
    try {
      final update = await checkForUpdate();
      if (!mounted) return;
      setState(() {
        _update = update;
        _updateStatus = update == null ? strings.get('upToDate') : null;
      });
      if (update != null) await _offerUpdate(update);
    } on UpdateException catch (error) {
      if (!mounted) return;
      setState(() {
        _updateStatus = '${strings.get('updateFailed')}: ${error.message}';
      });
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _offerUpdate(UpdateInfo update) async {
    final strings = StringsScope.of(context);
    final notes = update.notes.length > 400
        ? '${update.notes.substring(0, 400)}…'
        : update.notes;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusLarge),
        ),
        title: Text(
          strings.get('updateAvailable'),
          style: const TextStyle(
            color: Tokens.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings
                    .get('updateAvailableBody')
                    .replaceAll('{version}', update.version),
                style: const TextStyle(
                  color: Tokens.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  notes,
                  style: const TextStyle(
                    color: Tokens.textMuted,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              strings.get('later'),
              style: const TextStyle(color: Tokens.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              strings.get('download'),
              style: const TextStyle(
                color: Tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (open != true) return;
    try {
      await openUrl(update.downloadUrl);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _updateStatus = '${strings.get('updateFailed')}: $error';
      });
    }
  }

  Future<void> _changeName() async {
    final strings = StringsScope.of(context);
    final field = TextEditingController(text: _controller.name);
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
    if (name.isEmpty || name == _controller.name) return;
    try {
      await _controller.updateProfile(name: name);
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().contains('already taken')
          ? strings.get('nameTakenLong')
          : strings.get('saveFailed');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _changePhoto() async {
    final avatar = await pickAvatarBase64();
    if (avatar == null || !mounted) return;
    try {
      await _controller.updateProfile(avatarBase64: avatar);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(StringsScope.of(context).get('saveFailed'))),
      );
    }
  }

  Future<bool> _confirm({
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

  Future<void> _deleteIdentity() async {
    final strings = StringsScope.of(context);
    final confirmed = await _confirm(
      title: strings.get('deleteConfirmTitle'),
      body: strings.get('deleteIdentityBody'),
      action: strings.get('delete'),
    );
    if (!confirmed || !mounted) return;
    final navigator = Navigator.of(context);
    final dataDir = _controller.dataDir;
    await _controller.wipe();
    if (!mounted) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => WelcomeScreen(
          controller: _controller,
          dataDir: dataDir,
          onEntered: () => navigator.pop(),
        ),
      ),
    );
  }

  Future<void> _quit() async {
    final strings = StringsScope.of(context);
    final confirmed = await _confirm(
      title: strings.get('quitConfirmTitle'),
      body: strings.get('quitBody'),
      action: strings.get('quit'),
      danger: false,
    );
    if (!confirmed) return;
    await _controller.shutdown();
    exit(0);
  }

  void _applyCustom(Color color) {
    if (accentTooClose(color)) return;
    _controller.settings.setAccent(color);
  }

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);

    return SafeArea(
      bottom: false,
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, _controller.settings]),
        builder: (context, _) {
          final settings = _controller.settings;
          final people = _controller.people
              .where((person) => !person.visible)
              .toList();

          return ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              widget.embedded ? 18 : 12,
              20,
              widget.embedded ? 120 : 32,
            ),
            children: [
              Row(
                children: [
                  if (!widget.embedded) ...[
                    NeuIconButton(
                      icon: Icons.arrow_back_rounded,
                      accent: true,
                      size: 44,
                      iconSize: 20,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Text(
                    strings.get('settings'),
                    style: TextStyle(
                      fontSize: widget.embedded ? 24 : 22,
                      fontWeight: FontWeight.w800,
                      color: Tokens.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ProfileCard(
                controller: _controller,
                onChangeName: _changeName,
                onChangePhoto: _changePhoto,
                onRemovePhoto: () =>
                    _controller.updateProfile(removeAvatar: true),
              ),
              const SizedBox(height: 24),
              _SectionTitle(text: strings.get('appearance')),
              const SizedBox(height: 10),
              Text(
                strings.get('accentBody'),
                style: const TextStyle(
                  color: Tokens.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final preset in Tokens.accentPresets)
                    _AccentSwatch(
                      color: preset.color,
                      selected:
                          settings.accent.toARGB32() == preset.color.toARGB32(),
                      onTap: () => _applyCustom(preset.color),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _CustomColor(
                open: _customOpen,
                value: _custom ?? HSVColor.fromColor(settings.accent),
                onToggle: () => setState(() => _customOpen = !_customOpen),
                onChanged: (value) {
                  setState(() => _custom = value);
                  if (!accentTooClose(value.toColor())) {
                    settings.setAccent(value.toColor());
                  }
                },
              ),
              if (accentTooClose(
                (_custom ?? HSVColor.fromColor(settings.accent)).toColor(),
              ))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    strings.get('colorTooClose'),
                    style: const TextStyle(
                      color: Tokens.danger,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              _AppearancePreview(accent: settings.accent, strings: strings),
              const SizedBox(height: 26),
              _SectionTitle(text: strings.get('language')),
              const SizedBox(height: 10),
              _LanguageChoice(
                language: settings.language,
                onChanged: settings.setLanguage,
              ),
              const SizedBox(height: 26),
              _SectionTitle(text: strings.get('settings')),
              const SizedBox(height: 10),
              Neu(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    _ToggleRow(
                      icon: Icons.motion_photos_off_rounded,
                      title: strings.get('reduceMotion'),
                      subtitle: strings.get('reduceMotionBody'),
                      value: settings.reduceMotion,
                      onChanged: settings.setReduceMotion,
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: withOpacity(Colors.white, 0.04),
                    ),
                    _ToggleRow(
                      icon: Icons.notifications_none_rounded,
                      title: strings.get('notifications'),
                      subtitle: strings.get('notificationsBody'),
                      value: settings.notifications,
                      onChanged: settings.setNotifications,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              _SectionTitle(text: strings.get('security')),
              const SizedBox(height: 10),
              Neu(
                padding: EdgeInsets.zero,
                child: _LinkRow(
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
              ),
              const SizedBox(height: 26),
              if (supportsBatteryExemption) ...[
                Neu(
                  padding: EdgeInsets.zero,
                  child: _LinkRow(
                    icon: Icons.battery_saver_rounded,
                    title: strings.get('batteryTitle'),
                    subtitle: strings.get('batteryBody'),
                    onTap: requestBatteryExemption,
                  ),
                ),
                const SizedBox(height: 26),
              ],
              _SectionTitle(text: strings.get('hiddenPeople')),
              const SizedBox(height: 10),
              if (people.isEmpty)
                Neu(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Text(
                    strings.get('noHiddenPeople'),
                    style: const TextStyle(
                      color: Tokens.textSecondary,
                      fontSize: 12.5,
                    ),
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
                            indent: 64,
                            color: withOpacity(Colors.white, 0.04),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          child: Row(
                            children: [
                              KinlyAvatar(
                                name: people[index].name,
                                avatarBase64: people[index].avatar,
                                size: 38,
                                showDot: false,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  people[index].name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Tokens.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _controller.setVisibility(
                                  people[index].deviceId,
                                  true,
                                ),
                                child: Text(
                                  strings.get('showMeAgain'),
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 26),
              _SectionTitle(text: strings.get('about')),
              const SizedBox(height: 10),
              Neu(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Neu(
                          width: 40,
                          height: 40,
                          radius: 14,
                          accent: true,
                          child: Icon(
                            Icons.forum_rounded,
                            size: 20,
                            color: readableOn(settings.accent),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.get('appName'),
                                style: const TextStyle(
                                  color: Tokens.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${strings.get('version')} $appVersion · '
                                '${strings.get('madeBy')}',
                                style: const TextStyle(
                                  color: Tokens.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      strings.get('aboutBody'),
                      style: const TextStyle(
                        color: Tokens.textSecondary,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    if (Platform.isAndroid) ...[
                      const SizedBox(height: 4),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: withOpacity(Colors.white, 0.04),
                      ),
                      InkWell(
                        onTap: _checkingUpdate
                            ? null
                            : _update != null
                            ? () => _offerUpdate(_update!)
                            : _checkUpdates,
                        borderRadius: BorderRadius.circular(
                          Tokens.radiusMedium,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              if (_checkingUpdate)
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                )
                              else
                                Icon(
                                  _update == null
                                      ? Icons.system_update_alt_rounded
                                      : Icons.download_rounded,
                                  size: 18,
                                  color: _update == null
                                      ? Tokens.textMuted
                                      : Theme.of(context).colorScheme.primary,
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _checkingUpdate
                                          ? strings.get('checkingUpdates')
                                          : strings.get('checkUpdates'),
                                      style: TextStyle(
                                        color: _update == null
                                            ? Tokens.textPrimary
                                            : Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (_updateStatus != null) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        _updateStatus!,
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
                              if (_update != null)
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: Tokens.textMuted,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Neu(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _LinkRow(
                      icon: Icons.delete_outline_rounded,
                      title: strings.get('deleteIdentity'),
                      subtitle: strings.get('deleteIdentityBody'),
                      danger: true,
                      onTap: _deleteIdentity,
                    ),
                    if (Platform.isLinux) ...[
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: 58,
                        color: withOpacity(Colors.white, 0.04),
                      ),
                      _LinkRow(
                        icon: Icons.logout_rounded,
                        title: strings.get('quit'),
                        subtitle: strings.get('quitBody'),
                        onTap: _quit,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

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

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
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

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected ? Tokens.textPrimary : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: withOpacity(color, 0.35),
                blurRadius: selected ? 14 : 6,
                spreadRadius: selected ? 1 : 0,
              ),
            ],
          ),
          child: selected
              ? Icon(Icons.check_rounded, size: 20, color: readableOn(color))
              : null,
        ),
      ),
    );
  }
}

class _CustomColor extends StatelessWidget {
  const _CustomColor({
    required this.open,
    required this.value,
    required this.onToggle,
    required this.onChanged,
  });

  final bool open;
  final HSVColor value;
  final VoidCallback onToggle;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final color = value.toColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onToggle,
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: withOpacity(Colors.white, 0.2),
                    width: 1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                strings.get('customColor'),
                style: const TextStyle(
                  color: Tokens.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 18,
                color: Tokens.textMuted,
              ),
            ],
          ),
        ),
        if (open) ...[
          const SizedBox(height: 6),
          _ColorSlider(
            label: strings.get('hue'),
            value: value.hue,
            max: 360,
            color: color,
            onChanged: (hue) => onChanged(value.withHue(hue)),
          ),
          _ColorSlider(
            label: strings.get('saturation'),
            value: value.saturation,
            max: 1,
            color: color,
            onChanged: (saturation) =>
                onChanged(value.withSaturation(saturation)),
          ),
          _ColorSlider(
            label: strings.get('preview'),
            value: value.value,
            max: 1,
            color: color,
            onChanged: (brightness) => onChanged(value.withValue(brightness)),
          ),
        ],
      ],
    );
  }
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(color: Tokens.textMuted, fontSize: 11),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: color,
              inactiveTrackColor: withOpacity(Colors.white, 0.08),
              thumbColor: color,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(0, max),
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({required this.accent, required this.strings});

  final Color accent;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final onAccent = readableOn(accent);
    return Neu(
      inset: true,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.get('preview'),
            style: const TextStyle(color: Tokens.textMuted, fontSize: 10.5),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Tokens.surfaceHigh,
                borderRadius: BorderRadius.circular(Tokens.radiusMedium),
              ),
              child: Text(
                strings.get('noMessagesBody'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Tokens.textPrimary,
                  fontSize: 11.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(Tokens.radiusMedium),
              ),
              child: Text(
                strings.get('typing'),
                style: TextStyle(color: onAccent, fontSize: 11.5),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const AccentPill(label: '3'),
              const SizedBox(width: 10),
              Icon(Icons.mic_rounded, size: 18, color: accent),
              const SizedBox(width: 10),
              Icon(Icons.call_rounded, size: 18, color: accent),
              const Spacer(),
              Text(
                strings.get('online'),
                style: TextStyle(color: accent, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({required this.language, required this.onChanged});

  final String language;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    return Row(
      children: [
        Expanded(
          child: _Choice(
            label: strings.get('english'),
            selected: language == 'en',
            onTap: () => onChanged('en'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Choice(
            label: strings.get('arabic'),
            selected: language == 'ar',
            onTap: () => onChanged('ar'),
          ),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
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
            style: TextStyle(
              color: selected ? readableOn(accent) : Tokens.textSecondary,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                const SizedBox(height: 2),
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
          NeuToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: danger ? Tokens.danger : Tokens.textMuted,
            ),
            const SizedBox(width: 13),
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
                    const SizedBox(height: 3),
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
