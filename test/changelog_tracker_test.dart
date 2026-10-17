import 'package:app_changelog/app_changelog.dart';
import 'package:app_changelog/src/changelog_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

const _key = 'seen_version';

final _changelog = AppChangelog.parse('''
## 3.0.0
- Redesign

## 3.0.0-beta.1
- Beta redesign

## 2.9.2
- @android: Android only

## 2.9.1
- Bug fixes

## 2.9.0
- New welcome screen

## 2.8.0
- Dark mode

## @ios: 2.8.5
- iOS hotfix
''');

/// A store backed by a map, standing in for `shared_preferences`.
class _Store {
  _Store([String? seen]) : values = {if (seen != null) _key: seen};

  final Map<String, String> values;
  int writes = 0;

  Future<String?> read(String key) async => values[key];

  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }
}

Future<ChangelogTracker> _start(
  _Store store, {
  required String version,
  String platform = 'ios',
  Future<bool> Function()? isExistingInstall,
}) =>
    ChangelogTracker.start(
      read: store.read,
      write: store.write,
      key: _key,
      version: version,
      platform: platform,
      isExistingInstall: isExistingInstall,
    );

List<String> _versions(List<PlatformRelease> releases) =>
    [for (final release in releases) release.version.toString()];

void main() {
  group('new install', () {
    test('is new, not updated, and stores the installed version', () async {
      final store = _Store();
      final ChangelogTracker tracker = await _start(store, version: '2.9.0');

      expect(tracker.isNewInstall, isTrue);
      expect(tracker.didUpdate, isFalse);
      expect(tracker.previousVersion, isNull);
      expect(store.values[_key], '2.9.0');
    });

    test('is not new on the next launch', () async {
      final store = _Store();
      await _start(store, version: '2.9.0');
      final ChangelogTracker tracker = await _start(store, version: '2.9.0');

      expect(tracker.isNewInstall, isFalse);
      expect(tracker.didUpdate, isFalse);
      expect(tracker.previousVersion, AppVersion.parse('2.9.0'));
    });

    test('has no unseen releases', () async {
      final ChangelogTracker tracker = await _start(_Store(), version: '2.9.0');
      expect(tracker.unseenReleases(_changelog), isEmpty);
    });

    test('treats an invalid stored value as nothing stored', () async {
      final store = _Store('not a version');
      final ChangelogTracker tracker = await _start(store, version: '2.9.0');

      expect(tracker.isNewInstall, isTrue);
      expect(store.values[_key], '2.9.0');
    });

    test('ignores isExistingInstall when it returns false', () async {
      final ChangelogTracker tracker = await _start(
        _Store(),
        version: '2.9.0',
        isExistingInstall: () async => false,
      );
      expect(tracker.isNewInstall, isTrue);
    });
  });

  group('update', () {
    test('is detected when the installed version is higher', () async {
      final ChangelogTracker tracker =
          await _start(_Store('2.8.0'), version: '2.9.1');

      expect(tracker.isNewInstall, isFalse);
      expect(tracker.didUpdate, isTrue);
      expect(tracker.previousVersion, AppVersion.parse('2.8.0'));
    });

    test('is not detected for the same version', () async {
      final ChangelogTracker tracker =
          await _start(_Store('2.9.1'), version: '2.9.1');
      expect(tracker.didUpdate, isFalse);
    });

    test('ignores build metadata', () async {
      final ChangelogTracker tracker =
          await _start(_Store('2.9.1+40'), version: '2.9.1+41');
      expect(tracker.didUpdate, isFalse);
    });

    test('is not detected after a downgrade', () async {
      final store = _Store('3.0.0');
      final ChangelogTracker tracker = await _start(store, version: '2.9.1');

      expect(tracker.didUpdate, isFalse);
      expect(tracker.unseenReleases(_changelog), isEmpty);
      expect(store.writes, 0);
    });

    test('does not write until the version is marked seen', () async {
      final store = _Store('2.8.0');
      await _start(store, version: '2.9.1');
      expect(store.writes, 0);
    });

    test('stays detected until the version is marked seen', () async {
      final store = _Store('2.8.0');
      await _start(store, version: '2.9.1');
      final ChangelogTracker tracker = await _start(store, version: '2.9.1');
      expect(tracker.didUpdate, isTrue);
    });
  });

  group('existing install', () {
    test('counts as updated when nothing is stored', () async {
      final store = _Store();
      final ChangelogTracker tracker = await _start(
        store,
        version: '2.9.1',
        isExistingInstall: () async => true,
      );

      expect(tracker.isNewInstall, isFalse);
      expect(tracker.didUpdate, isTrue);
      expect(tracker.previousVersion, isNull);
      expect(store.writes, 0);
    });

    test('only sees the installed version, not the whole history', () async {
      final ChangelogTracker tracker = await _start(
        _Store(),
        version: '2.9.1',
        isExistingInstall: () async => true,
      );
      expect(_versions(tracker.unseenReleases(_changelog)), ['2.9.1']);
    });

    test('is not asked once a version is stored', () async {
      var asked = false;
      await _start(
        _Store('2.8.0'),
        version: '2.9.1',
        isExistingInstall: () async => asked = true,
      );
      expect(asked, isFalse);
    });
  });

  group('markVersionSeen', () {
    test('stores the installed version and clears didUpdate', () async {
      final store = _Store('2.8.0');
      final ChangelogTracker tracker = await _start(store, version: '2.9.1');
      await tracker.markVersionSeen();

      expect(store.values[_key], '2.9.1');
      expect(tracker.didUpdate, isFalse);
      expect(tracker.unseenReleases(_changelog), isEmpty);
    });

    test('keeps isNewInstall and previousVersion for this launch', () async {
      final ChangelogTracker tracker =
          await _start(_Store('2.8.0'), version: '2.9.1');
      await tracker.markVersionSeen();

      expect(tracker.isNewInstall, isFalse);
      expect(tracker.previousVersion, AppVersion.parse('2.8.0'));
    });

    test('is not detected as an update on the next launch', () async {
      final store = _Store('2.8.0');
      await (await _start(store, version: '2.9.1')).markVersionSeen();
      final ChangelogTracker tracker = await _start(store, version: '2.9.1');
      expect(tracker.didUpdate, isFalse);
    });

    test('never stores a lower version', () async {
      final store = _Store('3.0.0');
      await (await _start(store, version: '2.9.1')).markVersionSeen();

      expect(store.values[_key], '3.0.0');
      expect(store.writes, 0);
    });

    test('stores the version for an existing install', () async {
      final store = _Store();
      final ChangelogTracker tracker = await _start(
        store,
        version: '2.9.1',
        isExistingInstall: () async => true,
      );
      await tracker.markVersionSeen();

      expect(store.values[_key], '2.9.1');
      expect(tracker.didUpdate, isFalse);
    });
  });

  group('unseenReleases', () {
    test('includes every release since the last seen version', () async {
      final ChangelogTracker tracker =
          await _start(_Store('2.8.0'), version: '2.9.1', platform: 'android');
      final List<PlatformRelease> releases = tracker.unseenReleases(_changelog);

      expect(_versions(releases), ['2.9.1', '2.9.0']);
      expect(releases.first.notes, ['Bug fixes']);
    });

    test('uses the platform-specific release history', () async {
      final ChangelogTracker ios =
          await _start(_Store('2.8.0'), version: '2.9.0');
      expect(_versions(ios.unseenReleases(_changelog)), ['2.9.0', '2.8.5']);

      final ChangelogTracker android =
          await _start(_Store('2.8.0'), version: '2.9.0', platform: 'android');
      expect(_versions(android.unseenReleases(_changelog)), ['2.9.0']);
    });

    test('skips releases with no notes for the platform', () async {
      final ChangelogTracker tracker =
          await _start(_Store('2.9.0'), version: '2.9.2');
      expect(_versions(tracker.unseenReleases(_changelog)), ['2.9.1']);
    });

    test('is empty when the installed version has nothing new', () async {
      final ChangelogTracker tracker =
          await _start(_Store('2.9.1'), version: '2.9.2');
      expect(tracker.didUpdate, isTrue);
      expect(tracker.unseenReleases(_changelog), isEmpty);
    });

    test('skips pre-releases on a stable version', () async {
      final ChangelogTracker tracker =
          await _start(_Store('2.9.2'), version: '3.0.0');
      expect(_versions(tracker.unseenReleases(_changelog)), ['3.0.0']);
    });

    test('includes pre-releases on a pre-release version', () async {
      final ChangelogTracker tracker =
          await _start(_Store('2.9.1'), version: '3.0.0-beta.1');
      expect(_versions(tracker.unseenReleases(_changelog)), ['3.0.0-beta.1']);
    });
  });

  test('throws for an invalid installed version', () {
    expect(_start(_Store(), version: '2.9'), throwsFormatException);
  });
}
