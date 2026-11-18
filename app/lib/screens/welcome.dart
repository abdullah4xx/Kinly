import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../state/node_controller.dart';
import '../theme/neu.dart';
import '../theme/tokens.dart';
import '../util/avatar_picker.dart';
import '../widgets/avatar.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.controller,
    required this.dataDir,
    required this.onEntered,
  });

  final NodeController controller;
  final String dataDir;
  final VoidCallback onEntered;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _name = TextEditingController();
  final _focus = FocusNode();
  String? _avatar;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _validName {
    final value = _name.text.trim();
    return value.isNotEmpty && value.characters.length <= 32;
  }

  Future<void> _pickPhoto() async {
    final avatar = await pickAvatarBase64();
    if (avatar == null || !mounted) return;
    setState(() => _avatar = avatar);
  }

  Future<void> _enter() async {
    final strings = StringsScope.of(context);
    if (_busy) return;
    if (!_validName) {
      setState(() => _error = strings.get('nameEmpty'));
      _focus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final name = _name.text.trim();
    await widget.controller.start(dataDir: widget.dataDir, name: name);
    if (!mounted) return;
    final startError = widget.controller.startError;
    if (startError != null) {
      setState(() {
        _busy = false;
        _error = startError.contains('already taken')
            ? strings.get('nameTakenLong')
            : startError;
      });
      await widget.controller.reset();
      return;
    }

    // A real uniqueness check needs the network: connect, give peers a moment
    // to reject the name, then enter if nobody objected.
    if (widget.controller.people.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      if (!mounted) return;
      if (widget.controller.nameConflict) {
        await widget.controller.reset();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = strings.get('nameTakenLong');
        });
        return;
      }
    }

    if (_avatar != null) {
      try {
        await widget.controller.updateProfile(avatarBase64: _avatar);
      } catch (_) {
        // The name is set; a failed photo can be retried from Settings.
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onEntered();
  }

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 36),
                    Neu(
                      width: 104,
                      height: 104,
                      radius: 34,
                      accent: true,
                      child: Icon(
                        Icons.forum_rounded,
                        size: 46,
                        color: readableOn(accent),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      strings.get('welcomeTitle'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Tokens.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      strings.get('welcomeBody'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.55,
                        color: Tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 34),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        strings.get('nameLabel'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Tokens.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Neu(
                      inset: true,
                      radius: Tokens.radiusLarge,
                      child: TextField(
                        controller: _name,
                        focusNode: _focus,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _enter(),
                        maxLength: 32,
                        style: const TextStyle(
                          color: Tokens.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: strings.get('nameHint'),
                          hintStyle: const TextStyle(
                            color: Tokens.textMuted,
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          prefixIcon: const Icon(
                            Icons.person_outline_rounded,
                            color: Tokens.textMuted,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _busy ? null : _pickPhoto,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_avatar == null)
                                NeuIconButton(
                                  icon: Icons.add_a_photo_outlined,
                                  size: 44,
                                  iconSize: 18,
                                  onPressed: _busy ? null : _pickPhoto,
                                )
                              else
                                KinlyAvatar(
                                  name: _name.text.trim(),
                                  avatarBase64: _avatar,
                                  size: 44,
                                  showDot: false,
                                ),
                              const SizedBox(width: 12),
                              Text(
                                _avatar == null
                                    ? strings.get('photoOptional')
                                    : strings.get('changePhoto'),
                                style: const TextStyle(
                                  color: Tokens.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_avatar != null) ...[
                          const Spacer(),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _avatar = null),
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
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Tokens.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            Tokens.radiusMedium,
                          ),
                          border: Border.all(
                            color: Tokens.danger.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Tokens.danger,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Tokens.danger,
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: AccentButton(
                        label: strings.get('enter'),
                        icon: Icons.arrow_forward_rounded,
                        expand: true,
                        busy: _busy,
                        onPressed: _busy ? null : _enter,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      '${strings.get('appName')} · v0.0.1',
                      style: const TextStyle(
                        color: Tokens.textMuted,
                        fontSize: 11,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
