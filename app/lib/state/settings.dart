import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/tokens.dart';

/// Local-only preferences: accent, language, motion, wallpaper, background
/// receiving and the app lock.
class AppSettings extends ChangeNotifier {
  AppSettings._(
    this._prefs,
    this._accent,
    this._language,
    this._reduceMotion,
    this._backgroundReceive,
    this._appLock,
    this._wallpaper,
    this._chatWallpapers,
  );

  static const _accentKey = 'accent_color';
  static const _languageKey = 'language';
  static const _motionKey = 'reduce_motion';
  static const _backgroundKey = 'background_receive';
  static const _appLockKey = 'app_lock';
  static const _wallpaperKey = 'chat_wallpaper';
  static const _chatWallpapersKey = 'chat_wallpapers';
  static const _nameKey = 'last_name';

  final SharedPreferences _prefs;
  Color _accent;
  String _language;
  bool _reduceMotion;
  bool _backgroundReceive;
  bool _appLock;
  String _wallpaper;
  final Map<String, String> _chatWallpapers;

  Color get accent => _accent;
  String get language => _language;
  bool get reduceMotion => _reduceMotion;
  bool get backgroundReceive => _backgroundReceive;
  bool get appLock => _appLock;
  String get wallpaper => _wallpaper;
  bool get isArabic => _language == 'ar';

  /// Kept for older callers; the toggle now controls background receiving.
  bool get notifications => _backgroundReceive;

  /// Last name used on this device, so a returning user can start the node
  /// without typing it again. The node database remains the source of truth.
  String? get cachedName => _prefs.getString(_nameKey);

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_accentKey);
    final accent = stored == null ? Tokens.defaultAccent : Color(stored);
    Map<String, String> chatWallpapers = const {};
    final raw = prefs.getString(_chatWallpapersKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          chatWallpapers = decoded.map(
            (key, value) => MapEntry(key, '$value'),
          );
        }
      } catch (_) {
        // A corrupt preferences entry must not stop the app from starting.
      }
    }
    return AppSettings._(
      prefs,
      accent,
      prefs.getString(_languageKey) ?? 'en',
      prefs.getBool(_motionKey) ?? false,
      prefs.getBool(_backgroundKey) ?? prefs.getBool('notifications') ?? true,
      prefs.getBool(_appLockKey) ?? false,
      prefs.getString(_wallpaperKey) ?? 'none',
      chatWallpapers,
    );
  }

  Future<void> setAccent(Color color) async {
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

  Future<void> setBackgroundReceive(bool value) async {
    _backgroundReceive = value;
    await _prefs.setBool(_backgroundKey, value);
    notifyListeners();
  }

  /// Kept for older callers; forwards to [setBackgroundReceive].
  Future<void> setNotifications(bool value) => setBackgroundReceive(value);

  Future<void> setAppLock(bool value) async {
    _appLock = value;
    await _prefs.setBool(_appLockKey, value);
    notifyListeners();
  }

  Future<void> setWallpaper(String id) async {
    _wallpaper = id;
    await _prefs.setString(_wallpaperKey, id);
    notifyListeners();
  }

  /// The wallpaper for [peer], falling back to the global default.
  String wallpaperFor(String peer) => _chatWallpapers[peer] ?? _wallpaper;

  /// Overrides the wallpaper for one chat; pass null to follow the default.
  Future<void> setChatWallpaper(String peer, String? id) async {
    if (id == null) {
      _chatWallpapers.remove(peer);
    } else {
      _chatWallpapers[peer] = id;
    }
    await _prefs.setString(_chatWallpapersKey, jsonEncode(_chatWallpapers));
    notifyListeners();
  }

  Future<void> forgetName() async {
    await _prefs.remove(_nameKey);
  }

  Duration duration(Duration normal) =>
      reduceMotion ? Duration.zero : normal;
}
