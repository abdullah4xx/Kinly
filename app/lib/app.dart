import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/strings.dart';
import 'screens/home.dart';
import 'screens/lock_screen.dart';
import 'screens/welcome.dart';
import 'state/node_controller.dart';
import 'state/settings.dart';
import 'theme/neu.dart';
import 'theme/tokens.dart';

class KinlyApp extends StatelessWidget {
  const KinlyApp({
    super.key,
    required this.settings,
    required this.controller,
    required this.dataDir,
    required this.knownName,
    required this.initError,
  });

  final AppSettings settings;
  final NodeController controller;
  final String dataDir;
  final String? knownName;
  final String? initError;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final strings = Strings(settings.language);
        return MaterialApp(
          title: strings.appName,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(settings.accent, settings.language),
          locale: strings.locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            return StringsScope(
              strings: strings,
              child: Directionality(
                textDirection: strings.direction,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: RootGate(
            settings: settings,
            controller: controller,
            dataDir: dataDir,
            knownName: knownName,
            initError: initError,
          ),
        );
      },
    );
  }
}

/// Decides between the welcome screen, the splash while the node starts, and
/// the main shell. Also renders a recovery screen when the Rust core fails.
class RootGate extends StatefulWidget {
  const RootGate({
    super.key,
    required this.settings,
    required this.controller,
    required this.dataDir,
    required this.knownName,
    required this.initError,
  });

  final AppSettings settings;
  final NodeController controller;
  final String dataDir;
  final String? knownName;
  final String? initError;

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> with WidgetsBindingObserver {
  static const _sessionGrace = Duration(minutes: 2);

  bool _entered = false;
  bool _unlocked = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A returning device already has a name, so the welcome screen is skipped
    // and the node starts right away. A fresh device must see the welcome
    // screen first; that screen starts the node when the name is entered.
    _entered = widget.knownName != null;
    if (widget.knownName != null && widget.initError == null) {
      widget.controller.start(dataDir: widget.dataDir, name: widget.knownName!);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _backgroundedAt = DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      // The biometric session is only valid for a short grace period after
      // the app was backgrounded.
      final backgrounded = _backgroundedAt;
      _backgroundedAt = null;
      if (backgrounded != null) {
        final elapsed = DateTime.now().difference(backgrounded);
        if (elapsed > _sessionGrace) {
          setState(() => _unlocked = false);
        }
      }
    }
  }

  bool get _needsLock => widget.settings.appLock && !_unlocked;

  Future<void> _unlock() async {
    setState(() => _unlocked = true);
  }

  @override
  void didUpdateWidget(RootGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.settings.appLock && !oldWidget.settings.appLock) {
      // Turning the lock on re-arms the gate even for an already-unlocked
      // session.
      setState(() => _unlocked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    if (widget.initError != null) {
      return _FatalScreen(
        title: strings.get('startError'),
        detail: widget.initError!,
      );
    }
    if (!_entered) {
      if (_needsLock) {
        return LockScreen(onUnlocked: _unlock);
      }
      return WelcomeScreen(
        controller: widget.controller,
        dataDir: widget.dataDir,
        onEntered: () => setState(() => _entered = true),
      );
    }
    if (_needsLock) {
      return LockScreen(onUnlocked: _unlock);
    }
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (controller.startError != null) {
          return _FatalScreen(
            title: strings.get('startError'),
            detail: controller.startError!,
            onRetry: () async {
              await controller.reset();
              if (!mounted) return;
              final known = widget.knownName;
              if (known != null) {
                await controller.start(dataDir: widget.dataDir, name: known);
              } else {
                setState(() => _entered = false);
              }
            },
          );
        }
        if (!controller.ready) {
          if (_needsLock) {
            return LockScreen(onUnlocked: _unlock);
          }
          return const _SplashScreen();
        }
        if (_needsLock) {
          return LockScreen(onUnlocked: _unlock);
        }
        return HomeShell(controller: controller);
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final strings = StringsScope.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Neu(
              width: 96,
              height: 96,
              radius: 32,
              accent: true,
              child: Icon(
                Icons.forum_rounded,
                size: 42,
                color: readableOn(accent),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: accent),
            ),
            const SizedBox(height: 18),
            Text(
              strings.get('starting'),
              style: const TextStyle(color: Tokens.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _FatalScreen extends StatelessWidget {
  const _FatalScreen({required this.title, required this.detail, this.onRetry});

  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Tokens.danger,
                size: 44,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Tokens.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Tokens.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 26),
                AccentButton(
                  label: strings.get('retry'),
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
