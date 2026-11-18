import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinly/util/update.dart';
import 'package:kinly/version.dart';

void main() {
  group('versionFromTag', () {
    test('reads the version out of release tags', () {
      expect(versionFromTag('apk-1.0.1'), '1.0.1');
      expect(versionFromTag('v1.2.3'), '1.2.3');
      expect(versionFromTag('release/2.0'), '2.0');
      expect(versionFromTag('nightly'), isNull);
    });
  });

  group('isNewerVersion', () {
    test('compares each numeric part', () {
      expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(isNewerVersion('2.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.0.1', '1.0.1'), isFalse);
      expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
      expect(isNewerVersion('1.0', '1.0.0'), isFalse);
    });
  });

  test('pubspec version matches the version shown in the app', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(match!.group(1), appVersion);
  });
}
