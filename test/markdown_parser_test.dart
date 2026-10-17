import 'dart:io';

import 'package:app_changelog/app_changelog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Expects parsing [markdown] to fail at [line] with a message containing
/// every string in [messageParts].
void expectMarkdownError(
  String markdown, {
  required int? line,
  required List<String> messageParts,
}) {
  expect(
    () => AppChangelog.parse(markdown),
    throwsA(
      isA<ChangelogFormatException>()
          .having((e) => e.line, 'line', line)
          .having(
              (e) => e.message, 'message', stringContainsInOrder(messageParts)),
    ),
  );
}

void main() {
  group('Markdown parsing', () {
    test('parses the documented example in source order', () {
      final changelog = AppChangelog.parse(markdownChangelog);
      expect(changelog.releases.map((r) => r.label), [
        '4.0.0',
        '3.12.1',
        '2.9.0',
        '@ios: 2.11.1',
        '@android: 2.10.1',
      ]);
    });

    test('parses shared releases', () {
      final ChangelogRelease release =
          AppChangelog.parse(markdownChangelog).releases[0];
      expect(release.isShared, isTrue);
      expect(release.version, AppVersion.parse('4.0.0'));
      expect(release.platform, isNull);
      expect(release.appliesTo('ios'), isTrue);
      expect(release.appliesTo('android'), isTrue);
      expect(release.appliesTo('web'), isTrue);
      expect(release.changes.map((c) => c.text), [
        'Major fixes',
        'Fix firebase',
        'Bug fixes and improvements',
      ]);
    });

    test('parses platform-specific releases', () {
      final List<ChangelogRelease> releases =
          AppChangelog.parse(markdownChangelog).releases;
      final ChangelogRelease ios = releases[3];
      expect(ios.isShared, isFalse);
      expect(ios.platform, 'ios');
      expect(ios.version, AppVersion.parse('2.11.1'));
      expect(ios.appliesTo('ios'), isTrue);
      expect(ios.appliesTo('android'), isFalse);
      expect(releases[4].platform, 'android');
      expect(releases[4].version, AppVersion.parse('2.10.1'));
    });

    test('stores platform tags as metadata, not display text', () {
      final ChangelogRelease release =
          AppChangelog.parse(markdownChangelog).releases[2];
      expect(release.changes.first.text, 'iPad pencil support');
      expect(release.changes.first.platform, 'ios');
      expect(release.changes.first.isShared, isFalse);
      expect(release.changes[1].platform, isNull);
      expect(release.changes[1].isShared, isTrue);
      expect(release.changes[4].text, 'Accessibility improvements');
      expect(release.changes[4].platform, 'android');
    });

    test('uses "What\'s new" when no title is given', () {
      final List<ChangelogRelease> releases =
          AppChangelog.parse(markdownChangelog).releases;
      expect(releases[0].title, "What's new");
      expect(releases[0].title, ChangelogRelease.defaultTitle);
    });

    test('uses an explicit title', () {
      final changelog = AppChangelog.parse('''
## 1.0.0

### Welcome to version one
- Launch
''');
      expect(changelog.releases.single.title, 'Welcome to version one');
    });

    test('supports custom platform identifiers', () {
      final changelog = AppChangelog.parse('''
## @web: 1.4.0
- @web: Keyboard shortcuts

## 1.3.0
- @macos: Menu bar extra
- @web: Offline mode
''');
      expect(changelog.releases[0].platform, 'web');
      expect(changelog.releases[1].changes.map((c) => c.platform), [
        'macos',
        'web',
      ]);
    });

    test('normalizes platform identifiers to lowercase', () {
      final changelog = AppChangelog.parse('''
## @iOS: 1.0.0
- @IOS: Fixed tabs
''');
      final ChangelogRelease release = changelog.releases.single;
      expect(release.platform, 'ios');
      expect(release.changes.single.platform, 'ios');
    });

    test('accepts "*" and "+" list markers and flexible tag spacing', () {
      final changelog = AppChangelog.parse('''
## @ios : 1.0.0
* @ios :Spaced tag
+ Plus item
''');
      final ChangelogRelease release = changelog.releases.single;
      expect(release.platform, 'ios');
      expect(release.changes.map((c) => c.text), ['Spaced tag', 'Plus item']);
    });

    test('joins indented continuation lines', () {
      final changelog = AppChangelog.parse('''
## 1.0.0
- @ios: A long change that
  wraps onto a second line
    and a third
- Next
''');
      final List<ChangelogChange> changes = changelog.releases.single.changes;
      expect(
        changes.first.text,
        'A long change that wraps onto a second line and a third',
      );
      expect(changes.first.platform, 'ios');
      expect(changes.last.text, 'Next');
    });

    test('keeps @ text that is not a platform tag', () {
      final changelog = AppChangelog.parse(r'''
## 1.0.0
- @mentions are now supported
- Email support@example.com: reply faster
- \@team: thanks for the feedback
''');
      final List<ChangelogChange> changes = changelog.releases.single.changes;
      expect(changes.map((c) => c.text), [
        '@mentions are now supported',
        'Email support@example.com: reply faster',
        '@team: thanks for the feedback',
      ]);
      expect(changes.every((c) => c.isShared), isTrue);
    });

    test('ignores the preamble, blank lines and HTML comments', () {
      final changelog = AppChangelog.parse('''
# Changelog

Some introduction with - dashes and ### hashes.

### Not a release

<!-- Release notes below -->
## 1.0.0

<!-- internal note -->

- First

- Second
''');
      expect(
        changelog.releases.single.changes.map((c) => c.text),
        ['First', 'Second'],
      );
    });

    test('handles Windows line endings and a byte order mark', () {
      final changelog = AppChangelog.parse(
        '﻿## 1.0.0\r\n\r\n### Title\r\n- @ios: One\r\n- Two\r\n',
      );
      final ChangelogRelease release = changelog.releases.single;
      expect(release.title, 'Title');
      expect(release.changes.map((c) => c.text), ['One', 'Two']);
    });

    test('allows releases without changes', () {
      final changelog = AppChangelog.parse('''
## 2.0.0
### Nothing to see here

## 1.0.0
''');
      expect(changelog.releases, hasLength(2));
      expect(changelog.releases[0].changes, isEmpty);
      expect(changelog.releases[0].title, 'Nothing to see here');
      expect(changelog.releases[1].changes, isEmpty);
    });

    test('parses dated release headings', () {
      final changelog = AppChangelog.parse('''
## 1.2.1 - 2024-01-31
- Shared

## @ios: 1.2.0 – 2023-12-01
- iOS

## 1.0.0
- Initial
''');
      final List<ChangelogRelease> releases = changelog.releases;
      expect(releases.map((r) => r.label), ['1.2.1', '@ios: 1.2.0', '1.0.0']);
      expect(releases[0].date, DateTime.utc(2024, 1, 31));
      expect(releases[1].date, DateTime.utc(2023, 12, 1));
      expect(releases[2].date, isNull);
      expect(
        changelog.find(platform: 'ios', version: '1.2.1')?.date,
        DateTime.utc(2024, 1, 31),
      );
    });

    test('shares changes between stacked platform headings', () {
      final changelog = AppChangelog.parse('''
## @android: 1.2.1 - 2024-01-31

## @ios: 1.0.1
### iPad update
- Shared
- @android: Android only
- @ios: iOS only

## 1.0.0
- Initial
''');
      expect(changelog.releases.map((r) => r.label), [
        '@android: 1.2.1',
        '@ios: 1.0.1',
        '1.0.0',
      ]);
      expect(changelog.releases.map((r) => r.line), [1, 3, 9]);

      final PlatformRelease? android =
          changelog.find(platform: 'android', version: '1.2.1');
      expect(android?.title, 'iPad update');
      expect(android?.date, DateTime.utc(2024, 1, 31));
      expect(android?.notes, ['Shared', 'Android only']);

      final PlatformRelease? ios =
          changelog.find(platform: 'ios', version: '1.0.1');
      expect(ios?.title, 'iPad update');
      expect(ios?.date, isNull);
      expect(ios?.notes, ['Shared', 'iOS only']);

      expect(changelog.find(platform: 'ios', version: '1.2.1'), isNull);
      expect(changelog.find(platform: 'web', version: '1.0.1'), isNull);
    });

    test('does not stack shared headings', () {
      final changelog = AppChangelog.parse('''
## 2.0.0
## @ios: 1.0.1
## @android: 1.0.1
- Fix

## @web: 1.0.0
## 0.9.0
- Initial
''');
      expect(changelog.releases.map((r) => r.label), [
        '2.0.0',
        '@ios: 1.0.1',
        '@android: 1.0.1',
        '@web: 1.0.0',
        '0.9.0',
      ]);
      expect(changelog.releases[0].changes, isEmpty);
      expect(changelog.releases[1].changes.single.text, 'Fix');
      expect(changelog.releases[2].changes.single.text, 'Fix');
      expect(changelog.releases[3].changes, isEmpty);
    });

    test('returns an empty changelog for empty input', () {
      expect(AppChangelog.parse('').releases, isEmpty);
      expect(AppChangelog.parse('# Changelog\n').releases, isEmpty);
    });

    test('parses pre-release and build metadata versions', () {
      final changelog = AppChangelog.parse('''
## 3.0.0-beta.1+7
- Beta
''');
      expect(changelog.releases.single.label, '3.0.0-beta.1+7');
    });
  });

  group('Markdown errors', () {
    test('reports an invalid version', () {
      expectMarkdownError(
        '# Log\n\n## Unreleased\n- Thing\n',
        line: 3,
        messageParts: ['Invalid version "Unreleased"', 'semantic versioning'],
      );
      expectMarkdownError(
        '## 2.9\n',
        line: 1,
        messageParts: ['Invalid version "2.9"'],
      );
    });

    test('reports a heading without a version', () {
      expectMarkdownError(
        '## 1.0.0\n- a\n##\n',
        line: 3,
        messageParts: ['missing a version'],
      );
      expectMarkdownError(
        '## @ios:\n',
        line: 1,
        messageParts: ['"## @ios:" is missing a version'],
      );
    });

    test('reports invalid platform identifiers in headings', () {
      expectMarkdownError(
        '## @: 1.0.0\n',
        line: 1,
        messageParts: ['Invalid platform identifier ""'],
      );
      expectMarkdownError(
        '## @1os: 1.0.0\n',
        line: 1,
        messageParts: [
          'Invalid platform identifier "1os"',
          'start with a letter'
        ],
      );
      expectMarkdownError(
        '## @ios!: 1.0.0\n',
        line: 1,
        messageParts: ['Invalid platform identifier "ios!"'],
      );
      expectMarkdownError(
        '## @ios 1.0.0\n',
        line: 1,
        messageParts: [
          'Invalid platform release heading',
          '## @platform: version'
        ],
      );
    });

    test('reports invalid platform identifiers in changes', () {
      expectMarkdownError(
        '## 1.0.0\n- ok\n- @i\$os: Broken\n',
        line: 3,
        messageParts: [r'Invalid platform identifier "i$os"'],
      );
    });

    test('reports a change tagged for a platform outside the release', () {
      expectMarkdownError(
        '## 1.0.0\n- a\n\n## @ios: 2.11.1\n- Shared fix\n- @android: Wrong\n',
        line: 4,
        messageParts: [
          '"@android: Wrong" targets "android"',
          'release "@ios: 2.11.1" only applies to ios',
        ],
      );
    });

    test('reports a change tagged for a platform outside stacked headings', () {
      expectMarkdownError(
        '## @android: 1.2.1\n## @ios: 1.0.1\n- Shared\n- @web: Wrong\n',
        line: 4,
        messageParts: [
          '"@web: Wrong" targets "web"',
          'release "@android: 1.2.1, @ios: 1.0.1" only applies to android and '
              'ios',
        ],
      );
    });

    test('reports a platform repeated in stacked headings', () {
      expectMarkdownError(
        '## @ios: 2.0.0\n\n## @ios: 1.9.0\n- Fix\n',
        line: 3,
        messageParts: [
          '"## @ios: 1.9.0" repeats the platform "ios"',
          '"## @ios: 2.0.0" (line 1)',
        ],
      );
    });

    test('reports an invalid release date', () {
      expectMarkdownError(
        '## 1.0.0 - 2024-02-30\n',
        line: 1,
        messageParts: ['Invalid date "2024-02-30"', 'YYYY-MM-DD'],
      );
      expectMarkdownError(
        '## @ios: 1.0.0 - Jan 1st\n',
        line: 1,
        messageParts: [
          'Invalid date "Jan 1st" in release heading "## @ios: 1.0.0 - Jan 1st"',
        ],
      );
      expectMarkdownError(
        '## 1.0.0 -\n',
        line: 1,
        messageParts: ['Invalid date ""'],
      );
    });

    test('reports empty changes', () {
      expectMarkdownError(
        '## 1.0.0\n- a\n-\n',
        line: 3,
        messageParts: ['A change cannot be empty'],
      );
      expectMarkdownError(
        '## 1.0.0\n- @ios:\n',
        line: 2,
        messageParts: ['targets "@ios" but has no text'],
      );
    });

    test('reports unexpected content', () {
      expectMarkdownError(
        '## 1.0.0\n- a\nReleased on Monday\n',
        line: 3,
        messageParts: [
          'Unexpected content in release "1.0.0": "Released on Monday"',
          'list items',
        ],
      );
      expectMarkdownError(
        '## 1.0.0\n    indented before any change\n',
        line: 2,
        messageParts: ['Unexpected content'],
      );
    });

    test('reports title problems', () {
      expectMarkdownError(
        '## 1.0.0\n### One\n### Two\n',
        line: 3,
        messageParts: ['already has the title "One"'],
      );
      expectMarkdownError(
        '## 1.0.0\n- a\n### Late\n',
        line: 3,
        messageParts: ['"### Late" must come before the changes'],
      );
      expectMarkdownError(
        '## 1.0.0\n###\n',
        line: 2,
        messageParts: ['title of release "1.0.0" is empty'],
      );
    });

    test('reports unsupported headings and nested lists', () {
      expectMarkdownError(
        '## 1.0.0\n#### Deep\n',
        line: 2,
        messageParts: ['Unsupported heading "#### Deep"'],
      );
      expectMarkdownError(
        '## 1.0.0\n- a\n  - nested\n',
        line: 3,
        messageParts: ['Nested lists are not supported'],
      );
    });

    test('includes the line in toString', () {
      try {
        AppChangelog.parse('## nope\n');
        fail('Expected an exception');
      } on ChangelogFormatException catch (e) {
        expect(e, isA<FormatException>());
        expect(e.toString(), startsWith('ChangelogFormatException: Line 1: '));
      }
    });
  });

  group('repository files', () {
    test("the package's own CHANGELOG.md is a valid changelog", () {
      final changelog = AppChangelog.parse(
        File('CHANGELOG.md').readAsStringSync(),
      );
      expect(changelog.releases, isNotEmpty);
    });

    test('the example changelog matches the fixture', () {
      final changelog = AppChangelog.parse(
        File('example/release_notes.md').readAsStringSync(),
      );
      expect(
          changelog.releases, AppChangelog.parse(markdownChangelog).releases);
    });
  });
}
