// A CI/CD helper that prints the latest changelog version for each platform.
//
// Usage:
//   dart run example/ci_latest_version.dart <changelog> <platform>...
//
// With one platform it prints just the version, ready for `--build-name`:
//   flutter build ipa \
//     --build-name="$(dart run example/ci_latest_version.dart CHANGELOG.md ios)" \
//     --build-number="$BUILD_NUMBER"
//
// With several platforms it prints `platform=version` lines, which can be
// appended to `$GITHUB_OUTPUT`, for example:
//   dart run example/ci_latest_version.dart CHANGELOG.md ios android
//   ios=2.11.1
//   android=2.10.1
//
// Pre-releases are skipped, since store build names must be plain
// MAJOR.MINOR.PATCH. Build numbers are left to your CI/CD platform.
import 'dart:io';

import 'package:app_changelog/app_changelog.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: dart run example/ci_latest_version.dart <changelog> <platform>...',
    );
    exit(64);
  }

  final String path = args.first;
  final List<String> platforms = args.skip(1).toList();

  final AppChangelog changelog;
  try {
    changelog = await AppChangelog.load(path: path);
  } on FileSystemException catch (e) {
    stderr.writeln('Could not read $path: ${e.message}');
    exit(66);
  } on ChangelogFormatException catch (e) {
    stderr.writeln('$path: $e');
    exit(65);
  }

  var missing = false;
  for (final platform in platforms) {
    final PlatformRelease? latest =
        changelog.latestFor(platform, includePreReleases: false);
    if (latest == null) {
      stderr.writeln('No stable release for "$platform" in $path.');
      missing = true;
      continue;
    }
    // Drop build metadata: the CI/CD platform owns the build number.
    final AppVersion v = latest.version;
    final buildName = '${v.major}.${v.minor}.${v.patch}';
    stdout.writeln(platforms.length == 1 ? buildName : '$platform=$buildName');
  }
  if (missing) exit(1);
}
