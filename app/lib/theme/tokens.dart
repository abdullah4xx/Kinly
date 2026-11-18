import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Design tokens from PLAN.md section 4. The background is never pure black and
/// the neumorphic shadows are neutral: only the accent carries colour.
abstract final class Tokens {
  static const background = Color(0xFF1C1F26);
  static const surface = Color(0xFF22262E);
  static const surfaceHigh = Color(0xFF262B34);
  static const surfaceLow = Color(0xFF181B21);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9AA0AA);
  static const textMuted = Color(0xFF6C727C);
  static const shadowDark = Color(0xFF0E1015);
  static const shadowLight = Color(0xFF2C313B);
  static const danger = Color(0xFFE8505B);
  static const success = Color(0xFF49C48A);

  static const defaultAccent = Color(0xFFE8505B);

  static const radiusLarge = 24.0;
  static const radiusMedium = 18.0;
  static const radiusRound = 999.0;

  static const gap = 16.0;
  static const pagePadding = EdgeInsets.symmetric(horizontal: 20);

  /// Preset accents shown in Settings -> Appearance. They all keep at least a
  /// 3:1 contrast ratio against the background.
  static const accentPresets = <({String name, Color color})>[
    (name: 'Coral', color: Color(0xFFE8505B)),
    (name: 'Amber', color: Color(0xFFE7A33E)),
    (name: 'Lime', color: Color(0xFF9BCB4A)),
    (name: 'Mint', color: Color(0xFF49C48A)),
    (name: 'Sky', color: Color(0xFF4AA8E8)),
    (name: 'Violet', color: Color(0xFF9B7BE8)),
    (name: 'Rose', color: Color(0xFFE86FA8)),
  ];
}

/// WCAG relative luminance.
double relativeLuminance(Color color) {
  double channel(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG contrast ratio between two opaque colours (1:1 to 21:1).
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Text colour on top of [background], picking the option with the best
/// contrast. Used for sent bubbles and accent buttons.
Color readableOn(Color background) {
  final white = contrastRatio(Colors.white, background);
  final black = contrastRatio(Colors.black, background);
  return white >= black ? Colors.white : Colors.black;
}

/// A colour is blocked when it is too close to the background to be seen.
bool accentTooClose(Color accent) {
  return contrastRatio(accent, Tokens.background) < 3.0;
}

/// White text on the accent is only allowed at 4.5:1; otherwise black is used.
bool accentAllowsWhiteText(Color accent) {
  return contrastRatio(Colors.white, accent) >= 4.5;
}

Color withOpacity(Color color, double opacity) {
  return color.withValues(alpha: opacity);
}

ThemeData buildTheme(Color accent, String language) {
  final onAccent = readableOn(accent);
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: Tokens.background,
    canvasColor: Tokens.background,
    fontFamily: language == 'ar' ? 'Noto Naskh Arabic' : null,
  );

  return base.copyWith(
    colorScheme: ColorScheme.dark(
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      onSecondary: onAccent,
      surface: Tokens.surface,
      onSurface: Tokens.textPrimary,
      error: Tokens.danger,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: Tokens.textPrimary,
      displayColor: Tokens.textPrimary,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: withOpacity(Colors.white, 0.04),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Tokens.surfaceHigh,
      contentTextStyle: const TextStyle(color: Tokens.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMedium),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Tokens.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: const TextStyle(color: Tokens.textPrimary, fontSize: 12),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
  );
}
