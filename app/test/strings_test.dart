import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinly/l10n/strings.dart';
import 'package:kinly/theme/tokens.dart';
import 'package:kinly/util/format.dart';

void main() {
  group('strings', () {
    test('every key has English and Arabic text', () {
      expect(Strings.keys, isNotEmpty);
      for (final key in Strings.keys) {
        expect(const Strings('en').get(key), isNotEmpty, reason: key);
        expect(const Strings('ar').get(key), isNotEmpty, reason: key);
      }
    });

    test('Arabic is right to left and English is left to right', () {
      expect(const Strings('ar').direction, TextDirection.rtl);
      expect(const Strings('en').direction, TextDirection.ltr);
      expect(const Strings('ar').locale, const Locale('ar'));
    });

    test('unknown keys fall back to the key itself', () {
      expect(const Strings('en').get('missing.key'), 'missing.key');
    });
  });

  group('contrast', () {
    test('readableOn always clears 4.5:1', () {
      for (final preset in Tokens.accentPresets) {
        final ratio = contrastRatio(
          readableOn(preset.color),
          preset.color,
        );
        expect(ratio, greaterThanOrEqualTo(4.5), reason: preset.name);
      }
    });

    test('accentTooClose warns about colours that vanish into the background', () {
      expect(accentTooClose(Tokens.background), isTrue);
      expect(accentTooClose(Color(0xFF000000)), isTrue);
      for (final preset in Tokens.accentPresets.where(
        (p) => p.color.toARGB32() != Color(0xFF000000).toARGB32(),
      )) {
        expect(accentTooClose(preset.color), isFalse, reason: preset.name);
      }
    });
  });

  group('formatBytes', () {
    test('uses whole bytes below 1 KiB', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('scales to KiB, MiB and GiB', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
    });
  });
}
