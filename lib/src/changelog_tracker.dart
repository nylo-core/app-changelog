import 'app_changelog.dart';
import 'changelog_release.dart';
import 'version_comparator.dart';

/// Tracks the last app version whose release notes the user has seen.
///
/// [AppChangelog.track] starts one when the app launches, and the tracking
/// members on [AppChangelog] delegate to it. Not exported.
class ChangelogTracker {
  ChangelogTracker._({
    required Future<void> Function(String key, String value) write,
    required String key,
    required this.version,
    required this.platform,
    required this.isNewInstall,
    required AppVersion? seen,
  })  : _write = write,
        _key = key,
        _seen = seen,
        previousVersion = isNewInstall ? null : seen;

  /// Reads the stored version and works out [isNewInstall] and [didUpdate].
  ///
  /// A missing or invalid stored value means a new install, and [version] is
  /// stored straight away, unless [isExistingInstall] returns `true`.
  ///
  /// Throws a [FormatException] if [version] is not a valid semantic version.
  static Future<ChangelogTracker> start({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
    required String key,
    required String version,
    required String platform,
    Future<bool> Function()? isExistingInstall,
  }) async {
    final installed = AppVersion.parse(version);
    final String? stored = await read(key);
    final AppVersion? seen =
        stored == null ? null : AppVersion.tryParse(stored);

    final bool isNewInstall =
        seen == null && !(await isExistingInstall?.call() ?? false);
    if (isNewInstall) await write(key, installed.toString());

    return ChangelogTracker._(
      write: write,
      key: key,
      version: installed,
      platform: platform,
      isNewInstall: isNewInstall,
      seen: isNewInstall ? installed : seen,
    );
  }

  final Future<void> Function(String key, String value) _write;
  final String _key;

  /// The last version marked as seen, or `null` for an existing install
  /// with nothing stored.
  AppVersion? _seen;

  /// The installed app version.
  final AppVersion version;

  /// The platform the app is running on, such as `ios`.
  final String platform;

  /// Whether this is the first launch since the app was installed.
  final bool isNewInstall;

  /// The last version marked as seen before this launch, or `null` on a new
  /// install or for an existing install with nothing stored.
  final AppVersion? previousVersion;

  /// Whether [version] is newer than the last version marked as seen.
  bool get didUpdate {
    final AppVersion? seen = _seen;
    return !isNewInstall && (seen == null || version > seen);
  }

  /// Stores [version] as seen, unless an equal or higher version is already
  /// stored.
  Future<void> markVersionSeen() async {
    final AppVersion? seen = _seen;
    if (seen != null && version <= seen) return;
    await _write(_key, version.toString());
    _seen = version;
  }

  /// The releases in [changelog] that the user hasn't seen, newest first.
  ///
  /// These are the releases on [platform] above the last version marked as
  /// seen and up to [version], skipping releases with no notes. Pre-releases
  /// are skipped unless [version] is itself a pre-release. For an existing
  /// install with nothing stored, only [version]'s release is included.
  List<PlatformRelease> unseenReleases(AppChangelog changelog) {
    if (!didUpdate) return [];
    final AppVersion? seen = _seen;
    return [
      for (final PlatformRelease release in changelog.releasesFor(platform))
        if (!release.isEmpty &&
            release.version <= version &&
            (seen == null
                ? release.version == version
                : release.version > seen) &&
            (version.isPreRelease || !release.version.isPreRelease))
          release,
    ];
  }
}
