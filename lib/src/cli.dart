import 'dart:io';

import 'app_changelog.dart';
import 'changelog_exception.dart';
import 'changelog_release.dart';
import 'platform.dart';
import 'version_comparator.dart';

/// Exit codes, following the BSD `sysexits.h` conventions.
const _ok = 0;
const _failed = 1;
const _usage = 64;
const _badChangelog = 65;
const _missingChangelog = 66;

/// The platform folders a Flutter project can have, which [runCli] checks
/// for when no `--platform` is given.
const projectPlatforms = [
  'android',
  'ios',
  'macos',
  'web',
  'windows',
  'linux',
];

final _shortVersionPattern = RegExp(
  r'<key>CFBundleShortVersionString</key>\s*<string>([^<]*)</string>',
);

final _pubspecVersionPattern =
    RegExp(r'''^version:[ \t]*['"]?([^'"\s#]+)''', multiLine: true);

const _usageText = '''
Reads build names from CHANGELOG.md and checks it before a release.

Usage: dart run app_changelog <command> [options]

Commands:
  version   Print the newest version, for flutter build --build-name.
  check     Fail if the changelog can't be parsed, a platform has no release
            or no notes, or pubspec.yaml is ahead of the changelog.

Options:
  --platform <name>   A platform to read, such as ios. Repeat it or separate
                      names with commas. Defaults to the platform folders in
                      the current directory.
  --path <file>       The changelog to read. Defaults to CHANGELOG.md.
  --pre-releases      Include pre-releases such as 2.0.0-beta.1. Store build
                      names must be MAJOR.MINOR.PATCH, so they're skipped by
                      default.
  -h, --help          Show this help.

Examples:
  flutter build ipa --build-name=\$(dart run app_changelog version --platform ios)
  dart run app_changelog version --platform ios,android >> "\$GITHUB_OUTPUT"
  dart run app_changelog check''';

/// Runs the `app_changelog` command line with [arguments], writing results
/// to [out] and problems to [err], and returns the exit code.
///
/// Relative paths, and the platform folders found when no `--platform` is
/// given, are resolved against [directory].
Future<int> runCli(
  List<String> arguments, {
  required StringSink out,
  required StringSink err,
  String directory = '.',
}) async {
  final _Options options;
  try {
    options = _Options.parse(arguments);
  } on FormatException catch (e) {
    err
      ..writeln(e.message)
      ..writeln()
      ..writeln(_usageText);
    return _usage;
  }
  if (options.help) {
    out.writeln(_usageText);
    return _ok;
  }

  final File file = _resolve(directory, options.path);
  final AppChangelog changelog;
  try {
    changelog = AppChangelog.parse(await file.readAsString());
  } on FileSystemException {
    err.writeln('${options.path} not found.');
    return _missingChangelog;
  } on ChangelogFormatException catch (e) {
    err.writeln('${options.path}: $e');
    return _badChangelog;
  }

  final List<String> platforms =
      options.platforms ?? _detectPlatforms(directory, changelog);
  final command = _Command(changelog, options, platforms, out, err);
  return switch (options.command) {
    'version' => command.version(),
    _ => command.check(directory),
  };
}

class _Command {
  _Command(this.changelog, this.options, this.platforms, this.out, this.err);

  final AppChangelog changelog;
  final _Options options;
  final List<String> platforms;
  final StringSink out;
  final StringSink err;

  String get _path => options.path;

  /// Prints the newest version on each platform: just the version when there
  /// is one platform, or when every platform agrees and none was named, and
  /// `platform=version` lines otherwise.
  int version() {
    if (platforms.isEmpty) {
      err.writeln(
        'No platform folders found. Pass --platform, for example '
        '--platform ios.',
      );
      return _usage;
    }
    final latest = <String, PlatformRelease>{};
    for (final String platform in platforms) {
      final PlatformRelease? release = _latest(platform);
      if (release == null) return _failed;
      latest[platform] = release;
    }

    final Set<String> names = {
      for (final release in latest.values) _buildName(release.version),
    };
    if (platforms.length == 1 ||
        (options.platforms == null && names.length == 1)) {
      out.writeln(names.single);
    } else if (options.platforms == null) {
      err.writeln(
        'The platforms have different versions in $_path '
        '(${_list(latest)}). Pass --platform to choose one.',
      );
      return _failed;
    } else {
      latest.forEach(
        (platform, release) =>
            out.writeln('$platform=${_buildName(release.version)}'),
      );
    }
    return _ok;
  }

  /// Checks that every platform has a release with notes, and that
  /// pubspec.yaml isn't ahead of the changelog.
  int check(String directory) {
    var passed = true;
    final latest = <String, PlatformRelease>{};
    for (final String platform in platforms) {
      final PlatformRelease? release = _latest(platform);
      if (release == null) {
        passed = false;
      } else {
        latest[platform] = release;
      }
    }

    latest.forEach((platform, release) {
      if (!release.isEmpty) return;
      passed = false;
      final List<String> withNotes = [
        for (final String other in latest.keys)
          if (latest[other]!.version == release.version &&
              !latest[other]!.isEmpty)
            other,
      ];
      final String fix = withNotes.length == 1
          ? 'If only ${withNotes.single} ships, write '
              '"## @${withNotes.single}: ${release.version}". Otherwise, add '
              'a note for $platform.'
          : 'Add a note for $platform.';
      err.writeln(
        'Release ${release.version} has no notes for $platform in $_path. '
        '$fix',
      );
    });

    final File pubspec = _resolve(directory, 'pubspec.yaml');
    final String? pubspecVersion = pubspec.existsSync()
        ? _pubspecVersionPattern
            .firstMatch(pubspec.readAsStringSync())
            ?.group(1)
        : null;
    final AppVersion? newest = _newestVersion();
    if (pubspecVersion != null && newest != null) {
      final AppVersion? parsed = AppVersion.tryParse(pubspecVersion);
      if (parsed == null) {
        passed = false;
        err.writeln(
          'pubspec.yaml has the version "$pubspecVersion", which isn\'t a '
          'semantic version such as 1.2.3.',
        );
      } else if (parsed > newest) {
        passed = false;
        final String version = _buildName(parsed, preRelease: true);
        err.writeln(
          'pubspec.yaml is at $version, but the newest release in $_path is '
          '$newest. Add a "## $version" section to $_path.',
        );
      }
    }

    for (final String platform in ['ios', 'macos']) {
      if (platforms.contains(platform)) _checkBuildName(directory, platform);
    }

    if (!passed) return _failed;
    latest.forEach((platform, release) {
      final int count = release.notes.length;
      out.writeln(
        '$platform ${_buildName(release.version)} '
        '($count ${count == 1 ? 'note' : 'notes'})',
      );
    });
    out.writeln('$_path is ready to release.');
    return _ok;
  }

  /// Warns when [platform]'s Info.plist doesn't read its version from
  /// `--build-name`, as the Flutter template does. It doesn't fail the check,
  /// since the project may set its version another way.
  void _checkBuildName(String directory, String platform) {
    final File plist = _resolve(directory, '$platform/Runner/Info.plist');
    if (!plist.existsSync()) return;
    final String? version =
        _shortVersionPattern.firstMatch(plist.readAsStringSync())?.group(1);
    if (version == null || version.contains('FLUTTER_BUILD_NAME')) return;
    err.writeln(
      'Warning: $platform/Runner/Info.plist sets CFBundleShortVersionString '
      'to $version, so flutter build --build-name won\'t change the '
      '$platform version. Set it to \$(FLUTTER_BUILD_NAME) to use the '
      'changelog version.',
    );
  }

  /// The newest release on [platform], or `null` after reporting that there
  /// is none.
  PlatformRelease? _latest(String platform) {
    final PlatformRelease? release = changelog.latestFor(
      platform,
      includePreReleases: options.preReleases,
    );
    if (release != null) return release;
    final bool onlyPreReleases = changelog.releasesFor(platform).isNotEmpty;
    err.writeln(
      onlyPreReleases
          ? 'No stable release for $platform in $_path. Pass --pre-releases '
              'to include pre-releases.'
          : 'No release for $platform in $_path. Add a "## x.y.z" or '
              '"## @$platform: x.y.z" section.',
    );
    return null;
  }

  /// The highest version on any of [platforms], pre-releases included.
  AppVersion? _newestVersion() {
    AppVersion? newest;
    for (final String platform in platforms) {
      final AppVersion? version = changelog.latestFor(platform)?.version;
      if (version != null && (newest == null || version > newest)) {
        newest = version;
      }
    }
    return newest;
  }

  /// [version] without build metadata, since the CI/CD platform owns the
  /// build number. Pre-releases keep their suffix only when included.
  String _buildName(AppVersion version, {bool preRelease = false}) {
    final String core = '${version.major}.${version.minor}.${version.patch}';
    return (options.preReleases || preRelease) && version.isPreRelease
        ? '$core-${version.preRelease.join('.')}'
        : core;
  }

  String _list(Map<String, PlatformRelease> latest) => [
        for (final String platform in latest.keys)
          '$platform ${_buildName(latest[platform]!.version)}',
      ].join(', ');
}

/// The project's platform folders, followed by any other platform the
/// changelog names, such as `web` in `## @web: 1.0.0`.
List<String> _detectPlatforms(String directory, AppChangelog changelog) {
  final List<String> found = [
    for (final String platform in projectPlatforms)
      if (Directory(_resolve(directory, platform).path).existsSync()) platform,
  ];
  return found.isEmpty ? (changelog.platforms.toList()..sort()) : found;
}

File _resolve(String directory, String path) {
  final file = File(path);
  return file.isAbsolute
      ? file
      : File('$directory${Platform.pathSeparator}$path');
}

class _Options {
  _Options({
    required this.command,
    required this.platforms,
    required this.path,
    required this.preReleases,
    required this.help,
  });

  /// Parses [arguments], throwing a [FormatException] with a message for
  /// the user when they aren't valid.
  factory _Options.parse(List<String> arguments) {
    String? command;
    List<String>? platforms;
    var path = 'CHANGELOG.md';
    var preReleases = false;
    var help = false;

    for (var i = 0; i < arguments.length; i++) {
      final String argument = arguments[i];
      String value(String name) {
        if (argument.startsWith('$name=')) {
          return argument.substring(name.length + 1);
        }
        if (i + 1 >= arguments.length) {
          throw FormatException('$name needs a value.');
        }
        return arguments[++i];
      }

      if (argument == '-h' || argument == '--help') {
        help = true;
      } else if (argument == '--pre-releases') {
        preReleases = true;
      } else if (argument == '--platform' ||
          argument.startsWith('--platform=')) {
        for (final String name in value('--platform').split(',')) {
          final String? platform = tryNormalizePlatform(name);
          if (platform == null) {
            throw FormatException('"$name" isn\'t a platform name.');
          }
          (platforms ??= []).add(platform);
        }
      } else if (argument == '--path' || argument.startsWith('--path=')) {
        path = value('--path');
      } else if (argument.startsWith('-')) {
        throw FormatException('Unknown option $argument.');
      } else if (command == null &&
          (argument == 'version' || argument == 'check')) {
        command = argument;
      } else {
        throw FormatException('Unknown command "$argument".');
      }
    }

    if (command == null && !help) {
      throw const FormatException('Choose a command: version or check.');
    }
    return _Options(
      command: command ?? 'check',
      platforms: platforms?.toSet().toList(),
      path: path,
      preReleases: preReleases,
      help: help,
    );
  }

  final String command;

  /// The platforms passed with `--platform`, or `null` to detect them.
  final List<String>? platforms;
  final String path;
  final bool preReleases;
  final bool help;
}
