import 'dart:io';

import 'package:flutter/services.dart';

/// Wraps Android's BiometricPrompt. Kinly never stores biometric data or the
/// device PIN; Android shows the prompt and only returns success or failure.
class AppLockService {
  const AppLockService();

  static const _channel = MethodChannel('app.kinly.chat/lock');

  bool get isSupported => Platform.isAndroid;

  Future<bool> canAuthenticate() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('canAuthenticate') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isDeviceSecure() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isDeviceSecure') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shows the fingerprint/PIN prompt. Returns true only after success.
  Future<bool> authenticate({required String title, String subtitle = ''}) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('authenticate', {
            'title': title,
            'subtitle': subtitle,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
