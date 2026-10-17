import 'dart:convert';

import 'package:app_changelog/app_changelog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
}
