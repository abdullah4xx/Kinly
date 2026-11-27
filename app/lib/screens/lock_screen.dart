import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/app_lock.dart';
import '../theme/neu.dart';
import '../theme/tokens.dart';

/// Full-screen biometric gate. Shown by the root gate while the app lock is
/// on and the session has not been unlocked yet. Uses the device
/// credential/PIN fallback through Android's BiometricPrompt automatically.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const _service = AppLockService();

  bool _busy = false;

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _service.authenticate(
      title: StringsScope.of(context).get('appLockEnabled'),
      subtitle: StringsScope.of(context).get('appLockSubtitle'),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onUnlocked();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 24),
                Neu(
                  width: 110,
                  height: 110,
                  radius: Tokens.radiusRound,
                  inset: true,
                  child: Icon(
                    Icons.fingerprint_rounded,
                    size: 48,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  strings.get('appLockTitle'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Tokens.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  strings.get('appLockSubtitle'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Tokens.textSecondary,
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 34),
                AccentButton(
                  label: strings.get('unlock'),
                  icon: Icons.lock_open_rounded,
                  onPressed: _busy ? null : _unlock,
                  expand: true,
                  busy: _busy,
                ),
                const SizedBox(height: 14),
                Text(
                  strings.get('appLockBody'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Tokens.textMuted,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
