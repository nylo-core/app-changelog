import 'dart:io';

import 'package:app_changelog/src/cli.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Run = ({int code, String out, String err});

void main() {
  late Directory project;

  setUp(() => project = Directory.systemTemp.createTempSync('app_changelog'));
  tearDown(() => project.deleteSync(recursive: true));

  void write(String path, String contents) =>
      File('${project.path}/$path').writeAsStringSync(contents);

  void platformFolders(List<String> platforms) {
    for (final String platform in platforms) {
      Directory('${project.path}/$platform').createSync();
    }
  }

  Future<_Run> run(List<String> arguments) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final int code =
        await runCli(arguments, out: out, err: err, directory: project.path);
    return (code: code, out: out.toString(), err: err.toString());
  }

  group('version', () {
    test('prints the newest shared version when every platform agrees',
        () async {
      platformFolders(['android', 'ios']);
      write('CHANGELOG.md', '## 1.5.0\n- New\n\n## 1.4.1\n- Old\n');

      final _Run result = await run(['version']);
      expect(result.code, 0);
      expect(result.out, '1.5.0\n');
      expect(result.err, isEmpty);
    });

    test('prints one platform\'s version', () async {
      write(
        'CHANGELOG.md',
        '## @android: 1.2.1\n- Hotfix\n\n## 1.2.0\n- Shared\n',
      );

      expect((await run(['version', '--platform', 'ios'])).out, '1.2.0\n');
      expect((await run(['version', '--platform=android'])).out, '1.2.1\n');
    });

    test('prints platform=version lines for several platforms', () async {
      write(
        'CHANGELOG.md',
        '## @android: 1.2.1\n## @ios: 1.0.1\n\n- Shared\n',
      );

      final _Run result = await run(['version', '--platform', 'ios,android']);
      expect(result.code, 0);
      expect(result.out, 'ios=1.0.1\nandroid=1.2.1\n');
      expect(
        (await run(['version', '--platform', 'ios', '--platform', 'android']))
            .out,
        'ios=1.0.1\nandroid=1.2.1\n',
      );
    });

    test('asks for --platform when the detected platforms differ', () async {
      platformFolders(['android', 'ios']);
      write('CHANGELOG.md', '## @android: 1.2.1\n- Hotfix\n\n## 1.2.0\n- a\n');

      final _Run result = await run(['version']);
      expect(result.code, 1);
      expect(result.out, isEmpty);
      expect(
        result.err,
        contains('different versions in CHANGELOG.md (android 1.2.1, ios '
            '1.2.0). Pass --platform'),
      );
    });

    test('skips pre-releases unless --pre-releases is passed', () async {
      write('CHANGELOG.md', '## 2.0.0-beta.2\n- b\n\n## 1.9.0\n- a\n');

      expect((await run(['version', '--platform', 'ios'])).out, '1.9.0\n');
      expect(
        (await run(['version', '--platform', 'ios', '--pre-releases'])).out,
        '2.0.0-beta.2\n',
      );
    });

    test('drops build metadata, since CI owns the build number', () async {
      write('CHANGELOG.md', '## 1.5.0+42\n- a\n');

      expect((await run(['version', '--platform', 'ios'])).out, '1.5.0\n');
    });

    test('without platform folders, reads the platforms the changelog names',
        () async {
      write('CHANGELOG.md', '## @web: 3.0.0\n- a\n');

      expect((await run(['version'])).out, '3.0.0\n');
    });

    test('needs --platform when no platform can be found', () async {
      write('CHANGELOG.md', '## 1.0.0\n- a\n');

      final _Run result = await run(['version']);
      expect(result.code, 64);
      expect(result.err, contains('Pass --platform'));
    });

    test('fails when a platform has no release', () async {
      write('CHANGELOG.md', '## @ios: 1.0.1\n- a\n');

      final _Run result = await run(['version', '--platform', 'android']);
      expect(result.code, 1);
      expect(result.out, isEmpty);
      expect(result.err, contains('No release for android in CHANGELOG.md'));
    });

    test('fails when a platform has only pre-releases', () async {
      write('CHANGELOG.md', '## 2.0.0-beta.1\n- a\n');

      final _Run result = await run(['version', '--platform', 'ios']);
      expect(result.code, 1);
      expect(result.err, contains('No stable release for ios'));
    });

    test('reads the changelog at --path', () async {
      write('NOTES.md', '## 4.0.0\n- a\n');

      expect(
        (await run(['version', '--platform', 'ios', '--path', 'NOTES.md'])).out,
        '4.0.0\n',
      );
    });
  });

  group('check', () {
    test('passes and summarises each platform\'s release', () async {
      platformFolders(['android', 'ios']);
      write('pubspec.yaml', 'name: app\nversion: 1.2.0+7\n');
      write(
        'CHANGELOG.md',
        '# Changelog\n\n## 1.2.0\n- @ios: iPad support\n- Fixes\n',
      );

      final _Run result = await run(['check']);
      expect(result.code, 0);
      expect(result.err, isEmpty);
      expect(
        result.out,
        'android 1.2.0 (1 note)\nios 1.2.0 (2 notes)\n'
        'CHANGELOG.md is ready to release.\n',
      );
    });

    test('fails when a shared release has no notes for a platform', () async {
      platformFolders(['android', 'ios']);
      write('CHANGELOG.md', '## 1.2.1\n- @android: Hotfix\n\n## 1.2.0\n- a\n');

      final _Run result = await run(['check']);
      expect(result.code, 1);
      expect(result.out, isEmpty);
      expect(
        result.err,
        'Release 1.2.1 has no notes for ios in CHANGELOG.md. If only android '
        'ships, write "## @android: 1.2.1". Otherwise, add a note for ios.\n',
      );
    });

    test('fails when a platform has no release', () async {
      platformFolders(['android', 'ios']);
      write('CHANGELOG.md', '## @ios: 1.0.1\n- a\n');

      final _Run result = await run(['check']);
      expect(result.code, 1);
      expect(result.err, contains('No release for android'));
    });

    test('fails when pubspec.yaml is ahead of the changelog', () async {
      platformFolders(['android', 'ios']);
      write('pubspec.yaml', 'name: app\nversion: "1.3.0+1" # next\n');
      write('CHANGELOG.md', '## 1.2.0\n- a\n');

      final _Run result = await run(['check']);
      expect(result.code, 1);
      expect(
        result.err,
        'pubspec.yaml is at 1.3.0, but the newest release in CHANGELOG.md is '
        '1.2.0. Add a "## 1.3.0" section to CHANGELOG.md.\n',
      );
    });

    test('allows pubspec.yaml to lag, since --build-name sets the version',
        () async {
      platformFolders(['ios']);
      write('pubspec.yaml', 'name: app\nversion: 1.0.0+1\n');
      write('CHANGELOG.md', '## 1.2.0\n- a\n');

      expect((await run(['check'])).code, 0);
    });

    test('compares pubspec.yaml with pre-releases too', () async {
      platformFolders(['ios']);
      write('pubspec.yaml', 'name: app\nversion: 2.0.0-beta.1\n');
      write('CHANGELOG.md', '## 2.0.0-beta.1\n- b\n\n## 1.9.0\n- a\n');

      final _Run result = await run(['check']);
      expect(result.code, 0);
      expect(result.out, startsWith('ios 1.9.0 (1 note)\n'));
    });

    test('fails when pubspec.yaml has an invalid version', () async {
      platformFolders(['ios']);
      write('pubspec.yaml', 'name: app\nversion: 1.2\n');
      write('CHANGELOG.md', '## 1.2.0\n- a\n');

      final _Run result = await run(['check']);
      expect(result.code, 1);
      expect(result.err, contains('"1.2", which isn\'t a semantic version'));
    });

    test('reports every problem at once', () async {
      platformFolders(['android', 'ios', 'web']);
      write('pubspec.yaml', 'name: app\nversion: 9.0.0\n');
      write('CHANGELOG.md', '## @android: 1.2.1\n- @android: a\n');

      final _Run result = await run(['check']);
      expect(result.code, 1);
      expect(result.err.trim().split('\n'), [
        startsWith('No release for ios'),
        startsWith('No release for web'),
        startsWith('pubspec.yaml is at 9.0.0'),
      ]);
    });

    test('warns when Info.plist ignores --build-name', () async {
      platformFolders(['ios']);
      Directory('${project.path}/ios/Runner').createSync();
      write('CHANGELOG.md', '## 1.2.0\n- a\n');

      String plist(String version) => '<dict>\n'
          '\t<key>CFBundleShortVersionString</key>\n'
          '\t<string>$version</string>\n</dict>\n';

      write('ios/Runner/Info.plist', plist(r'$(FLUTTER_BUILD_NAME)'));
      expect((await run(['check'])).err, isEmpty);

      write('ios/Runner/Info.plist', plist(r'$(MARKETING_VERSION)'));
      final _Run result = await run(['check']);
      expect(result.code, 0);
      expect(
        result.err,
        r'Warning: ios/Runner/Info.plist sets CFBundleShortVersionString to '
        r"$(MARKETING_VERSION), so flutter build --build-name won't change "
        r'the ios version. Set it to $(FLUTTER_BUILD_NAME) to use the '
        'changelog version.\n',
      );
    });

    test('only checks the platforms passed with --platform', () async {
      platformFolders(['android', 'ios']);
      write('CHANGELOG.md', '## @ios: 1.0.1\n- a\n');

      expect((await run(['check', '--platform', 'ios'])).code, 0);
    });
  });

  group('errors', () {
    test('a malformed changelog reports the line', () async {
      write('CHANGELOG.md', '## 1.2.0\n- a\n\n## 1.3 (beta)\n- b\n');

      final _Run result = await run(['check']);
      expect(result.code, 65);
      expect(
        result.err,
        startsWith('CHANGELOG.md: ChangelogFormatException: Line 4: '),
      );
    });

    test('a missing changelog is named', () async {
      final _Run result = await run(['version', '--path', 'NOTES.md']);
      expect(result.code, 66);
      expect(result.err, 'NOTES.md not found.\n');
    });

    test('bad arguments print usage', () async {
      for (final arguments in [
        <String>[],
        ['deploy'],
        ['version', '--nope'],
        ['version', '--platform'],
        ['version', '--platform', 'i os'],
      ]) {
        final _Run result = await run(arguments);
        expect(result.code, 64, reason: '$arguments');
        expect(result.err, contains('Usage: dart run app_changelog'));
      }
    });

    test('--help prints usage', () async {
      final _Run result = await run(['--help']);
      expect(result.code, 0);
      expect(result.out, contains('Usage: dart run app_changelog'));
    });
  });
}
