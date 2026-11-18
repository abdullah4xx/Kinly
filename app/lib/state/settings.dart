import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/tokens.dart';

/// Local-only preferences: accent, language, motion and notifications.
class AppSettings extends ChangeNotifier {
  AppSettings._(
    this._prefs,
    this._accent,
    this._language,
    this._reduceMotion,
    this._notifications,
  );

  static const _accentKey = 'accent_color';
  static const _languageKey = 'language';
  static const _motionKey = 'reduce_motion';
  static const _notificationsKey = 'notifications';
  static const _nameKey = 'last_name';

  final SharedPreferences _prefs;
  Color _accent;
  String _language;
  bool _reduceMotion;
  bool _notifications;

  Color get accent => _accent;
  String get language => _language;
  bool get reduceMotion => _reduceMotion;
  bool get notifications => _notifications;
  bool get isArabic => _language == 'ar';

  /// Last name used on this device, so a returning user can start the node
  /// without typing it again. The node database remains the source of truth.
  String? get cachedName => _prefs.getString(_nameKey);

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_accentKey);
    final accent = stored == null ? Tokens.defaultAccent : Color(stored);
    final safeAccent = accentTooClose(accent) ? Tokens.defaultAccent : accent;
    return AppSettings._(
      prefs,
      safeAccent,
      prefs.getString(_languageKey) ?? 'en',
      prefs.getBool(_motionKey) ?? false,
      prefs.getBool(_notificationsKey) ?? true,
    );
  }

  Future<void> setAccent(Color color) async {
    if (accentTooClose(color)) return;
    _accent = color;
    await _prefs.setInt(_accentKey, color.toARGB32());
    notifyListeners();
  }

  Future<void> setLanguage(String language) async {
    if (language == _language) return;
    _language = language;
    await _prefs.setString(_languageKey, language);
    notifyListeners();
  }

  Future<void> setReduceMotion(bool value) async {
    _reduceMotion = value;
    await _prefs.setBool(_motionKey, value);
    notifyListeners();
  }

  Future<void> rememberName(String name) async {
    await _prefs.setString(_nameKey, name);
  }

  Future<void> setNotifications(bool value) async {
    _notifications = value;
    await _prefs.setBool(_notificationsKey, value);
    notifyListeners();
  }

  Future<void> forgetName() async {
    await _prefs.remove(_nameKey);
  }

  Duration duration(Duration normal) =>
      reduceMotion ? Duration.zero : normal;
}
