import 'package:app_changelog/app_changelog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final changelog = AppChangelog.parse(markdownChangelog);

  group('platform filtering', () {
    test('includes shared changes and changes for the platform, in order', () {
      final PlatformRelease ios =
          changelog.find(platform: 'ios', version: '2.9.0')!;
      expect(ios.platform, 'ios');
      expect(ios.version, AppVersion.parse('2.9.0'));
      expect(ios.title, "What's new");
      expect(ios.notes, [
        'iPad pencil support',
        'A brand-new welcome screen',
        'A new language picker with search',
        'Improved translations',
        'Bug fixes and improvements',
      ]);

      final PlatformRelease android =
          changelog.find(platform: 'android', version: '2.9.0')!;
      expect(android.notes, [
        'A brand-new welcome screen',
        'A new language picker with search',
        'Improved translations',
        'Accessibility improvements',
        'Bug fixes and improvements',
      ]);
    });

    test('shows only shared changes on other platforms', () {
      final PlatformRelease web =
          changelog.find(platform: 'web', version: '2.9.0')!;
      expect(web.notes, [
        'A brand-new welcome screen',
        'A new language picker with search',
        'Improved translations',
        'Bug fixes and improvements',
      ]);
    });

    test('strips platform prefixes from the display text', () {
      final PlatformRelease ios =
          changelog.find(platform: 'ios', version: '2.9.0')!;
      expect(ios.changes.first.text, 'iPad pencil support');
      expect(ios.changes.first.toString(), 'iPad pencil support');
      expect(ios.notes.any((note) => note.contains('@')), isFalse);
    });

    test('can leave a platform with no changes', () {
      final changelog = AppChangelog.parse('''
## 1.0.0
- @ios: iOS only
''');
      final PlatformRelease android =
          changelog.find(platform: 'android', version: '1.0.0')!;
      expect(android.changes, isEmpty);
      expect(android.isEmpty, isTrue);
    });

    test('treats platform names case-insensitively', () {
      expect(
        changelog.find(platform: 'iOS', version: '2.9.0'),
        changelog.find(platform: 'ios', version: '2.9.0'),
      );
      expect(changelog.latestFor('Android')?.platform, 'android');
    });
  });

  group('find', () {
    test('finds platform-specific releases only on their platform', () {
      expect(
        changelog.find(platform: 'ios', version: '2.11.1')?.notes,
        ['Bug fixes and improvements'],
      );
      expect(changelog.find(platform: 'android', version: '2.11.1'), isNull);
      expect(changelog.find(platform: 'ios', version: '2.10.1'), isNull);
    });

    test('returns null for versions that do not exist', () {
      expect(changelog.find(platform: 'ios', version: '9.9.9'), isNull);
      expect(changelog.find(platform: 'ios', version: '4.0.0-beta'), isNull);
    });

    test('ignores build metadata in the requested version', () {
      expect(
        changelog.find(platform: 'ios', version: '2.9.0+120')?.version,
        AppVersion.parse('2.9.0'),
      );
    });

    test('rejects an invalid version', () {
      expect(
        () => changelog.find(platform: 'ios', version: '2.9'),
        throwsFormatException,
      );
    });

    test('rejects an invalid platform', () {
      for (final platform in ['', ' ', '@ios', '1ios', 'i os']) {
        expect(
          () => changelog.find(platform: platform, version: '2.9.0'),
          throwsArgumentError,
          reason: platform,
        );
      }
      expect(() => changelog.latestFor(''), throwsArgumentError);
      expect(() => changelog.releasesFor('a b'), throwsArgumentError);
    });
  });

  group('latestFor and releasesFor', () {
    test('finds the highest version regardless of changelog order', () {
      final changelog = AppChangelog.parse('''
## 2.9.0
- Old

## 2.10.0
- New

## 2.1.0
- Older
''');
      expect(changelog.latestFor('ios')?.version.toString(), '2.10.0');
    });

    test('keeps independent iOS and Android histories', () {
      final changelog = AppChangelog.parse('''
## @ios: 2.11.1
- iOS fix

## @android: 2.10.1
- Android fix

## @android: 2.12.0
- Android feature

## 2.9.0
- Shared
''');
      expect(changelog.latestFor('ios')?.version.toString(), '2.11.1');
      expect(changelog.latestFor('android')?.version.toString(), '2.12.0');
      expect(changelog.latestFor('web')?.version.toString(), '2.9.0');
      expect(
        changelog.releasesFor('android').map((r) => r.version.toString()),
        ['2.12.0', '2.10.1', '2.9.0'],
      );
      expect(
        changelog.releasesFor('ios').map((r) => r.version.toString()),
        ['2.11.1', '2.9.0'],
      );
    });

    test('returns filtered releases for the documented example', () {
      expect(changelog.latestFor('ios')?.version.toString(), '4.0.0');
      expect(
        changelog.releasesFor('android').map((r) => r.version.toString()),
        ['4.0.0', '3.12.1', '2.10.1', '2.9.0'],
      );
      final PlatformRelease android290 = changelog.releasesFor('android').last;
      expect(android290.notes, isNot(contains('iPad pencil support')));
    });

    test('orders pre-releases correctly and can exclude them', () {
      final changelog = AppChangelog.parse('''
## 3.0.0-rc.1
- Release candidate

## 3.0.0-beta.2
- Beta

## 2.9.0
- Stable
''');
      expect(changelog.latestFor('ios')?.version.toString(), '3.0.0-rc.1');
      expect(
        changelog
            .latestFor('ios', includePreReleases: false)
            ?.version
            .toString(),
        '2.9.0',
      );

      final released = AppChangelog.parse('''
## 3.0.0-rc.1
- Release candidate

## 3.0.0
- Final
''');
      expect(released.latestFor('ios')?.version.toString(), '3.0.0');
    });

    test('returns null and empty lists when nothing applies', () {
      final changelog = AppChangelog.parse('## @ios: 1.0.0\n- Hi\n');
      expect(changelog.latestFor('android'), isNull);
      expect(changelog.releasesFor('android'), isEmpty);
      expect(AppChangelog.parse('').latestFor('ios'), isNull);
    });

    test('returns null when only pre-releases exist and are excluded', () {
      final changelog = AppChangelog.parse('## 1.0.0-beta\n- Beta\n');
      expect(changelog.latestFor('ios', includePreReleases: false), isNull);
    });
  });

  group('platforms', () {
    test('lists explicitly named platforms', () {
      expect(changelog.platforms, {'ios', 'android'});
      final custom = AppChangelog.parse('''
## 1.0.0
- @web: Offline mode
## @macos: 1.0.1
- Fix
''');
      expect(custom.platforms, {'web', 'macos'});
    });
  });

  group('duplicate detection', () {
    void expectConflict(String markdown, int line, List<String> parts) {
      expect(
        () => AppChangelog.parse(markdown),
        throwsA(
          isA<ChangelogFormatException>()
              .having((e) => e.line, 'line', line)
              .having(
                  (e) => e.message, 'message', stringContainsInOrder(parts)),
        ),
      );
    }

    test('rejects duplicate shared releases', () {
      expectConflict(
        '## 1.0.0\n- a\n\n## 1.0.0\n- b\n',
        4,
        ['Duplicate release 1.0.0', '"1.0.0" conflicts with "1.0.0" (line 1)'],
      );
    });

    test('rejects duplicate platform-specific releases', () {
      expectConflict(
        '## @ios: 1.0.0\n- a\n\n## @ios: 1.0.0\n- b\n',
        4,
        ['Duplicate release for "ios" 1.0.0'],
      );
    });

    test('treats versions differing only by build metadata as duplicates', () {
      expectConflict(
        '## 1.0.0+1\n\n## 1.0.0+2\n',
        3,
        ['Duplicate release 1.0.0'],
      );
    });

    test('rejects shared and platform-specific releases with one version', () {
      expectConflict(
        '## 2.9.0\n- a\n\n## @ios: 2.9.0\n- b\n',
        4,
        ['Ambiguous release 2.9.0', '"@ios: 2.9.0" conflicts with "2.9.0"'],
      );
      expectConflict(
        '## @android: 2.9.0\n- a\n\n## 2.9.0\n- b\n',
        4,
        ['Ambiguous release 2.9.0'],
      );
    });

    test('checks each stacked heading as its own release', () {
      expectConflict(
        '## 1.2.1\n- a\n\n## @android: 1.2.1\n## @ios: 1.0.1\n- b\n',
        4,
        ['Ambiguous release 1.2.1', '"@android: 1.2.1" conflicts with "1.2.1"'],
      );
    });

    test('allows the same version on different platforms', () {
      final changelog = AppChangelog.parse(
        '## @ios: 2.9.0\n- a\n\n## @android: 2.9.0\n- b\n',
      );
      expect(changelog.find(platform: 'ios', version: '2.9.0')?.notes, ['a']);
      expect(
        changelog.find(platform: 'android', version: '2.9.0')?.notes,
        ['b'],
      );
    });
  });

  group('models', () {
    test('can be built programmatically', () {
      final AppChangelog changelog = changelogFromReleases([
        ChangelogRelease(
          AppVersion.parse('1.0.0'),
          changes: [
            ChangelogChange('Shared'),
            ChangelogChange('Only iOS', platform: 'iOS'),
          ],
        ),
        ChangelogRelease(AppVersion.parse('1.0.1'), platform: 'Android'),
      ]);
      expect(changelog.find(platform: 'ios', version: '1.0.0')?.notes, [
        'Shared',
        'Only iOS',
      ]);
      expect(changelog.latestFor('android')?.title, "What's new");
      expect(changelog.platforms, {'ios', 'android'});
    });

    test('are immutable', () {
      final ChangelogRelease release = changelog.releases.first;
      final PlatformRelease notes = changelog.latestFor('ios')!;
      expect(changelog.releases.clear, throwsUnsupportedError);
      expect(release.changes.clear, throwsUnsupportedError);
      expect(notes.changes.clear, throwsUnsupportedError);
      expect(() => AppVersion.parse('1.0.0-a').preRelease.clear(),
          throwsUnsupportedError);
    });

    test('validate programmatic input', () {
      expect(
          () => ChangelogChange(' '), throwsA(isA<ChangelogFormatException>()));
      expect(
        () => ChangelogChange('x', platform: 'not valid'),
        throwsA(isA<ChangelogFormatException>()),
      );
      expect(
        () => ChangelogRelease(AppVersion.parse('1.0.0'), platform: 'a b'),
        throwsA(isA<ChangelogFormatException>()),
      );
      expect(
        () => ChangelogRelease(
          AppVersion.parse('1.0.0'),
          platform: 'ios',
          changes: [ChangelogChange('x', platform: 'android')],
        ),
        throwsA(isA<ChangelogFormatException>()),
      );
    });

    test('parse changes in app_changelog notation', () {
      expect(
        ChangelogChange.parse('@ios: iPad pencil support'),
        ChangelogChange('iPad pencil support', platform: 'ios'),
      );
      expect(ChangelogChange.parse('Plain').isShared, isTrue);
      expect(ChangelogChange.parse('@ios: x').appliesTo('IOS'), isTrue);
      expect(ChangelogChange.parse('@ios: x').appliesTo('android'), isFalse);
    });

    test('have readable toString output', () {
      expect(changelog.toString(), 'AppChangelog(5 releases)');
      expect(
        changelog.releases[3].toString(),
        'ChangelogRelease(@ios: 2.11.1, "What\'s new", 1 changes)',
      );
      expect(
        changelog.find(platform: 'ios', version: '2.11.1').toString(),
        'PlatformRelease(ios 2.11.1, "What\'s new", '
        '[Bug fixes and improvements])',
      );
    });
  });
}
