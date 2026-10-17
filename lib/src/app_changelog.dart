import 'changelog_exception.dart';
import 'changelog_release.dart';
import 'markdown_parser.dart';
import 'platform.dart';
import 'runtime/runtime.dart'
    if (dart.library.ui) 'runtime/runtime_flutter.dart'
    if (dart.library.io) 'runtime/runtime_io.dart' as runtime;
import 'version_comparator.dart';

/// A parsed, validated changelog covering every platform of an app.
///
/// Load one with [AppChangelog.load] or [AppChangelog.parse], then query it
/// per platform with [find], [latestFor] and [releasesFor]. Every query
/// returns notes already filtered for the requested platform.
///
/// For the common cases, the static helpers load and query in one call:
///
/// ```dart
/// final release = await AppChangelog.currentRelease();
/// print(release?.title);
/// print(release?.notes);
/// ```
///
/// Platform identifiers are case-insensitive: `'iOS'` and `'ios'` are the
/// same platform.
class AppChangelog {
  AppChangelog._(Iterable<ChangelogRelease> releases)
      : _releases = List.unmodifiable(releases) {
    _checkForDuplicates(_releases);
  }

  /// Parses a `CHANGELOG.md`-style Markdown changelog.
  ///
  /// ```markdown
  /// ## 2.9.0
  ///
  /// ### What's new
  /// - @ios: iPad pencil support
  /// - Bug fixes and improvements
  ///
  /// ## @android: 2.8.1
  ///
  /// - Fixed a crash on startup
  /// ```
  ///
  /// Throws a [ChangelogFormatException] describing the first problem found,
  /// including its line number.
  factory AppChangelog.parse(String source) =>
      AppChangelog._(parseMarkdownReleases(source));

  /// Loads and parses the changelog at [path], `CHANGELOG.md` by default.
  ///
  /// In a Flutter app, [path] is an asset key, so the file must be listed
  /// under `flutter: assets:` in `pubspec.yaml`. In a Dart script, such as a
  /// CI/CD step, [path] is a file path relative to the working directory.
  ///
  /// Throws a [ChangelogFormatException] if the changelog is malformed.
  static Future<AppChangelog> load({String path = 'CHANGELOG.md'}) async =>
      AppChangelog.parse(await runtime.readChangelog(path));

  /// The release notes for the installed app version on [currentPlatform],
  /// or `null` if the changelog at [path] has no release for it.
  ///
  /// The installed version is read with `package_info_plus`, and its build
  /// number is ignored. Only available in a Flutter app.
  ///
  /// Throws a [ChangelogFormatException] if the changelog is malformed, or a
  /// [FormatException] if the installed version is not a valid semantic
  /// version.
  static Future<PlatformRelease?> currentRelease({
    String path = 'CHANGELOG.md',
  }) async {
    final AppChangelog changelog = await load(path: path);
    final String version = await runtime.installedVersion();
    return changelog.find(platform: currentPlatform, version: version);
  }

  /// The release with the highest version on [platform] in the changelog at
  /// [path], or `null` if no release applies to it.
  ///
  /// [platform] defaults to [currentPlatform]. Pre-releases are included
  /// unless [includePreReleases] is `false`.
  ///
  /// Throws a [ChangelogFormatException] if the changelog is malformed.
  static Future<PlatformRelease?> latestRelease({
    String? platform,
    String path = 'CHANGELOG.md',
    bool includePreReleases = true,
  }) async {
    final AppChangelog changelog = await load(path: path);
    return changelog.latestFor(
      platform ?? currentPlatform,
      includePreReleases: includePreReleases,
    );
  }

  /// The platform the code is running on, as a changelog platform
  /// identifier: `web`, `ios`, `android`, `macos`, `windows` or `linux`.
  static String get currentPlatform => runtime.runningPlatform;

  /// Every release, unfiltered and in source order.
  final List<ChangelogRelease> _releases;

  /// The platforms named explicitly anywhere in the changelog, either by a
  /// platform-specific release or by a platform-specific change.
  ///
  /// Shared releases apply to every platform, including ones not listed
  /// here.
  Set<String> get platforms => {
        for (final release in _releases) ...[
          if (release.platform case final platform?) platform,
          for (final change in release.changes)
            if (change.platform case final platform?) platform,
        ],
      };

  /// The releases that apply to [platform], filtered for it and ordered from
  /// the highest version to the lowest.
  ///
  /// Throws an [ArgumentError] if [platform] is not a valid identifier.
  List<PlatformRelease> releasesFor(String platform) {
    final String normalized = checkPlatformArgument(platform);
    return [
      for (final release in _releases)
        if (release.forPlatform(normalized) case final filtered?) filtered,
    ]..sort((a, b) => b.version.compareTo(a.version));
  }

  /// The release with the highest version on [platform], filtered for it,
  /// or `null` if no release applies to [platform].
  ///
  /// Pre-releases are included unless [includePreReleases] is `false`.
  ///
  /// Throws an [ArgumentError] if [platform] is not a valid identifier.
  PlatformRelease? latestFor(
    String platform, {
    bool includePreReleases = true,
  }) {
    for (final PlatformRelease release in releasesFor(platform)) {
      if (includePreReleases || !release.version.isPreRelease) return release;
    }
    return null;
  }

  /// The release for [platform] at [version], filtered for [platform], or
  /// `null` if there is none.
  ///
  /// Build metadata in [version] is ignored, so `2.9.0+42` finds `2.9.0`.
  ///
  /// Throws an [ArgumentError] if [platform] is not a valid identifier, or a
  /// [FormatException] if [version] is not a valid semantic version.
  PlatformRelease? find({required String platform, required String version}) {
    final String normalized = checkPlatformArgument(platform);
    final target = AppVersion.parse(version);
    for (final ChangelogRelease release in _releases) {
      if (release.version == target && release.appliesTo(normalized)) {
        return release.forPlatform(normalized);
      }
    }
    return null;
  }

  @override
  String toString() => 'AppChangelog(${_releases.length} releases)';
}

/// Builds a changelog from [releases], for tests. Not exported.
AppChangelog changelogFromReleases(Iterable<ChangelogRelease> releases) =>
    AppChangelog._(releases);

/// The unfiltered releases of [changelog], in source order, for tests. Not
/// exported.
List<ChangelogRelease> releasesOf(AppChangelog changelog) =>
    changelog._releases;

void _checkForDuplicates(List<ChangelogRelease> releases) {
  final shared = <AppVersion, ChangelogRelease>{};
  final specific = <(String, AppVersion), ChangelogRelease>{};
  final specificByVersion = <AppVersion, ChangelogRelease>{};

  for (final release in releases) {
    final AppVersion version = release.version;
    final String? platform = release.platform;
    if (platform == null) {
      if (shared[version] case final existing?) {
        _throwConflict(release, existing, 'Duplicate release $version');
      }
      if (specificByVersion[version] case final existing?) {
        _throwAmbiguous(release, existing, version);
      }
      shared[version] = release;
    } else {
      if (specific[(platform, version)] case final existing?) {
        _throwConflict(
          release,
          existing,
          'Duplicate release for "$platform" $version',
        );
      }
      if (shared[version] case final existing?) {
        _throwAmbiguous(release, existing, version);
      }
      specific[(platform, version)] = release;
      specificByVersion.putIfAbsent(version, () => release);
    }
  }
}

Never _throwAmbiguous(
  ChangelogRelease release,
  ChangelogRelease existing,
  AppVersion version,
) =>
    _throwConflict(
      release,
      existing,
      'Ambiguous release $version: a shared release and a platform-specific '
      'release cannot have the same version. Merge them into one shared '
      'release and tag platform-specific changes with "@platform:"',
    );

Never _throwConflict(
  ChangelogRelease release,
  ChangelogRelease existing,
  String problem,
) {
  final where = existing.line == null ? '' : ' (line ${existing.line})';
  throw ChangelogFormatException(
    '$problem. "${release.label}" conflicts with "${existing.label}"$where.',
    line: release.line,
  );
}
