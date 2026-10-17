import 'package:app_changelog/app_changelog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppVersion.parse', () {
    test('parses major, minor and patch', () {
      final version = AppVersion.parse('2.11.1');
      expect(version.major, 2);
      expect(version.minor, 11);
      expect(version.patch, 1);
      expect(version.preRelease, isEmpty);
      expect(version.build, isNull);
      expect(version.isPreRelease, isFalse);
    });

    test('parses pre-release identifiers and build metadata', () {
      final version = AppVersion.parse('3.0.0-beta.2+42');
      expect(version.preRelease, ['beta', '2']);
      expect(version.build, '42');
      expect(version.isPreRelease, isTrue);
      expect(version.toString(), '3.0.0-beta.2+42');
    });

    test('trims surrounding whitespace', () {
      expect(AppVersion.parse('  1.2.3 ').toString(), '1.2.3');
    });

    for (final invalid in [
      '',
      '1',
      '1.2',
      '1.2.3.4',
      'v1.2.3',
      '01.2.3',
      '1.02.3',
      '1.2.3-',
      '1.2.3-01',
      '1.2.3+',
      'latest',
    ]) {
      test('rejects "$invalid"', () {
        expect(
          () => AppVersion.parse(invalid),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('semantic versioning'),
            ),
          ),
        );
        expect(AppVersion.tryParse(invalid), isNull);
      });
    }
  });

  group('AppVersion ordering', () {
    test('compares numerically, not as strings', () {
      expect(AppVersion.parse('2.10.0') > AppVersion.parse('2.9.0'), isTrue);
      expect(AppVersion.parse('10.0.0') > AppVersion.parse('9.99.99'), isTrue);
      expect(AppVersion.parse('2.9.10') > AppVersion.parse('2.9.9'), isTrue);
    });

    test('follows semantic versioning pre-release precedence', () {
      const ordered = [
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0-alpha.beta',
        '1.0.0-beta',
        '1.0.0-beta.2',
        '1.0.0-beta.11',
        '1.0.0-rc.1',
        '1.0.0',
        '1.0.1-alpha',
        '1.0.1',
      ];
      final List<AppVersion> shuffled =
          ordered.reversed.map(AppVersion.parse).toList()..sort();
      expect(shuffled.map((v) => v.toString()), ordered);
    });

    test('compares very large numeric pre-release identifiers', () {
      expect(
        AppVersion.parse('1.0.0-99999999999999999999') >
            AppVersion.parse('1.0.0-9999999999999999999'),
        isTrue,
      );
    });

    test('ignores build metadata for equality and precedence', () {
      final a = AppVersion.parse('1.2.3+1');
      final b = AppVersion.parse('1.2.3+2');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.compareTo(b), 0);
      expect(a.toString(), '1.2.3+1');
    });

    test('supports comparison operators', () {
      final low = AppVersion.parse('1.0.0');
      final high = AppVersion.parse('1.0.1');
      expect(low < high, isTrue);
      expect(low <= high, isTrue);
      expect(high > low, isTrue);
      expect(high >= low, isTrue);
      expect(low <= AppVersion.parse('1.0.0'), isTrue);
      expect(low >= AppVersion.parse('1.0.0'), isTrue);
    });
  });
}
