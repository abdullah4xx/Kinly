import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('app.kinly.chat/system');

/// Android asks the user to exempt apps from battery optimization; without it
/// the foreground service can be frozen and messages arrive late.
bool get supportsBatteryExemption => Platform.isAndroid;

Future<bool> isBatteryExempt() async {
  if (!Platform.isAndroid) return true;
  try {
    return await _channel.invokeMethod<bool>('isBatteryExempt') ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> requestBatteryExemption() async {
  if (!Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<void>('requestBatteryExemption');
  } catch (_) {
    // The channel is only present on Android; ignore failures elsewhere.
  }
}

/// Opens a web page or a download link in the system browser.
Future<void> openUrl(String url) async {
  if (Platform.isAndroid) {
    await _channel.invokeMethod<void>('openUrl', {'url': url});
    return;
  }
  final opener = Platform.isMacOS ? 'open' : 'xdg-open';
  await Process.run(opener, [url]);
}
