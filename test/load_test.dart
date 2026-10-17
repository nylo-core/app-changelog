import 'dart:convert';

import 'package:app_changelog/app_changelog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

const Map<String, String> _assets = {
  'CHANGELOG.md': markdownChangelog,
  'assets/release_notes.md': '## 9.9.9\n- Custom path\n',
  'broken.md': '## 2.9\n',
};

/// Serves [_assets] to `rootBundle` instead of the app's real assets.
void _mockAssets() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
    final String key = Uri.decodeFull(
      utf8.decode(message!.buffer.asUint8List(
        message.offsetInBytes,
        message.lengthInBytes,
      )),
    );
    final String? asset = _assets[key];
    return asset == null ? null : ByteData.sublistView(utf8.encode(asset));
  });
}

void _mockInstalledVersion(String version) {
  PackageInfo.setMockInitialValues(
    appName: 'Example',
    packageName: 'com.example.app',
    version: version,
    buildNumber: '42',
    buildSignature: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _mockAssets();
    rootBundle.clear();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('currentPlatform', () {
    test('is the lowercase target platform name', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(AppChangelog.currentPlatform, 'ios');
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(AppChangelog.currentPlatform, 'macos');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(AppChangelog.currentPlatform, 'android');
    });
  });

  group('load', () {
    test('reads CHANGELOG.md by default', () async {
      final AppChangelog changelog = await AppChangelog.load();
      expect(
        changelog.releases,
        AppChangelog.parse(markdownChangelog).releases,
      );
    });

    test('reads a custom path', () async {
      final AppChangelog changelog =
          await AppChangelog.load(path: 'assets/release_notes.md');
      expect(changelog.latestFor('ios')?.notes, ['Custom path']);
    });

    test('throws for a malformed changelog', () {
      expect(
        AppChangelog.load(path: 'broken.md'),
        throwsA(isA<ChangelogFormatException>()),
      );
    });
  });

  group('currentRelease', () {
    final changelog = AppChangelog.parse(markdownChangelog);

    test('finds the installed version for the current platform', () async {
      _mockInstalledVersion('2.9.0');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final PlatformRelease? release = await AppChangelog.currentRelease();
      expect(release?.platform, 'android');
      expect(release, changelog.find(platform: 'android', version: '2.9.0'));
    });

    test('uses the platform-specific release history', () async {
      _mockInstalledVersion('2.11.1');

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect((await AppChangelog.currentRelease())?.platform, 'ios');

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await AppChangelog.currentRelease(), isNull);
    });

    test('returns null for a version not in the changelog', () async {
      _mockInstalledVersion('9.9.9');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await AppChangelog.currentRelease(), isNull);
    });

    test('reads a custom path', () async {
      _mockInstalledVersion('9.9.9');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final PlatformRelease? release =
          await AppChangelog.currentRelease(path: 'assets/release_notes.md');
      expect(release?.notes, ['Custom path']);
    });
  });

  group('latestRelease', () {
    test('defaults to the current platform', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect((await AppChangelog.latestRelease())?.version.toString(), '4.0.0');
    });

    test('accepts a platform and a custom path', () async {
      final PlatformRelease? release = await AppChangelog.latestRelease(
        platform: 'android',
        path: 'assets/release_notes.md',
      );
      expect(release?.platform, 'android');
      expect(release?.notes, ['Custom path']);
    });

    test('can skip pre-releases', () async {
      final PlatformRelease? latest = await AppChangelog.latestRelease(
        platform: 'ios',
        includePreReleases: false,
      );
      expect(latest?.version.isPreRelease, isFalse);
    });
  });

  group('track', () {
    const key = 'app_changelog.seen_version';

    setUp(() {
      resetTracking();
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    Future<String?> storedVersion() async =>
        (await SharedPreferences.getInstance()).getString(key);

    test('stores a new install with shared_preferences', () async {
      _mockInstalledVersion('2.9.0');
      await AppChangelog.track();

      expect(AppChangelog.isNewInstall, isTrue);
      expect(AppChangelog.didUpdate, isFalse);
      expect(AppChangelog.previousVersion, isNull);
      expect(await storedVersion(), '2.9.0');
    });

    test('detects an update from shared_preferences', () async {
      SharedPreferences.setMockInitialValues({key: '2.9.0'});
      _mockInstalledVersion('4.0.0');
      await AppChangelog.track();

      expect(AppChangelog.isNewInstall, isFalse);
      expect(AppChangelog.didUpdate, isTrue);
      expect(AppChangelog.previousVersion, AppVersion.parse('2.9.0'));
    });

    test('marks the installed version as seen', () async {
      SharedPreferences.setMockInitialValues({key: '2.9.0'});
      _mockInstalledVersion('4.0.0');
      await AppChangelog.track();
      await AppChangelog.markVersionSeen();

      expect(AppChangelog.didUpdate, isFalse);
      expect(await storedVersion(), '4.0.0');
    });

    test('loads the unseen releases from the changelog', () async {
      SharedPreferences.setMockInitialValues({key: '2.9.0'});
      _mockInstalledVersion('4.0.0');
      await AppChangelog.track();

      final List<PlatformRelease> releases =
          await AppChangelog.unseenReleases();
      expect(
        [for (final release in releases) release.version.toString()],
        ['4.0.0', '3.12.1', '2.10.1'],
      );
      expect(
          releases.every((release) => release.platform == 'android'), isTrue);
    });

    test('reads unseen releases from a custom path', () async {
      SharedPreferences.setMockInitialValues({key: '2.9.0'});
      _mockInstalledVersion('9.9.9');
      await AppChangelog.track();

      final List<PlatformRelease> releases =
          await AppChangelog.unseenReleases(path: 'assets/release_notes.md');
      expect(releases.single.notes, ['Custom path']);
    });

    test('has no unseen releases without an update', () async {
      _mockInstalledVersion('2.9.0');
      await AppChangelog.track();
      expect(await AppChangelog.unseenReleases(path: 'broken.md'), isEmpty);
    });

    test('uses a custom key', () async {
      _mockInstalledVersion('2.9.0');
      await AppChangelog.track(key: 'whats_new');
      expect(
        (await SharedPreferences.getInstance()).getString('whats_new'),
        '2.9.0',
      );
      expect(await storedVersion(), isNull);
    });

    test('uses custom storage instead of shared_preferences', () async {
      final values = <String, String>{key: '2.9.0'};
      _mockInstalledVersion('4.0.0');
      await AppChangelog.track(
        read: (key) async => values[key],
        write: (key, value) async => values[key] = value,
      );
      await AppChangelog.markVersionSeen();

      expect(values[key], '4.0.0');
      expect(await storedVersion(), isNull);
    });

    test('passes isExistingInstall through', () async {
      _mockInstalledVersion('2.9.0');
      await AppChangelog.track(isExistingInstall: () async => true);

      expect(AppChangelog.isNewInstall, isFalse);
      expect(AppChangelog.didUpdate, isTrue);
    });

    test('throws when only one of read and write is given', () {
      expect(
        AppChangelog.track(read: (key) async => null),
        throwsArgumentError,
      );
    });

    test('throws when used before track', () {
      expect(() => AppChangelog.isNewInstall, throwsStateError);
      expect(() => AppChangelog.didUpdate, throwsStateError);
      expect(() => AppChangelog.previousVersion, throwsStateError);
      expect(AppChangelog.markVersionSeen, throwsStateError);
      expect(AppChangelog.unseenReleases(), throwsStateError);
    });
  });
}
