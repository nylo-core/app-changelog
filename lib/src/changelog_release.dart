import 'changelog_change.dart';
import 'changelog_exception.dart';
import 'platform.dart';
import 'version_comparator.dart';

/// A release as declared in a changelog, before filtering for a platform.
///
/// A release is either shared, applying to every platform, or
/// platform-specific, applying only to [platform].
///
/// Use [forPlatform] to get the notes a particular platform should display.
class ChangelogRelease {
  /// Creates a release at [version] that applies to every platform, or only
  /// to [platform] when given, optionally released on [date].
  ///
  /// Throws a [ChangelogFormatException] if [platform] is not a valid
  /// identifier, [title] is empty, or a change in a platform-specific
  /// release targets another platform.
  factory ChangelogRelease(
    AppVersion version, {
    String? platform,
    String? title,
    DateTime? date,
    Iterable<ChangelogChange> changes = const [],
    int? line,
  }) {
    final release = ChangelogRelease._(
      version: version,
      platform:
          platform == null ? null : normalizePlatform(platform, line: line),
      title: _checkTitle(title, line),
      date: date,
      changes: List.unmodifiable(changes),
      line: line,
    );
    for (final ChangelogChange change in release.changes) {
      if (!release.isShared &&
          !change.isShared &&
          change.platform != release.platform) {
        throw ChangelogFormatException(
          'The change "@${change.platform}: ${change.text}" targets '
          '"${change.platform}", but release "${release.label}" only applies '
          'to ${release.platform}. Remove the "@" prefix or move the change '
          'to a release for "${change.platform}".',
          line: line,
        );
      }
    }
    return release;
  }

  ChangelogRelease._({
    required this.version,
    required this.platform,
    required this.title,
    required this.date,
    required this.changes,
    required this.line,
  });

  /// The title used when a release does not specify one.
  static const defaultTitle = "What's new";

  /// The release version.
  final AppVersion version;

  /// The only platform this release applies to, or `null` if it applies to
  /// every platform.
  final String? platform;

  /// The release title, [defaultTitle] when none was given.
  final String title;

  /// The release date, such as the `2024-01-01` in `## 1.2.1 - 2024-01-01`,
  /// or `null` if none was given.
  final DateTime? date;

  /// Every change in the release, in source order, including changes that
  /// target specific platforms.
  final List<ChangelogChange> changes;

  /// The 1-based line where the release was declared in its source, if
  /// known. Ignored by equality.
  final int? line;

  /// Whether this release applies to every platform.
  bool get isShared => platform == null;

  /// A readable label for the release, such as `2.9.0` or `@ios: 2.11.1`.
  String get label => isShared ? '$version' : '@$platform: $version';

  /// Whether this release applies to [platform].
  ///
  /// Throws an [ArgumentError] if [platform] is not a valid identifier.
  bool appliesTo(String platform) =>
      isShared || this.platform == checkPlatformArgument(platform);

  /// Returns this release as [platform] should display it, or `null` if the
  /// release does not apply to [platform].
  ///
  /// The result keeps shared changes and changes targeting [platform], in
  /// their original order, and drops changes targeting other platforms.
  ///
  /// Throws an [ArgumentError] if [platform] is not a valid identifier.
  PlatformRelease? forPlatform(String platform) {
    final String normalized = checkPlatformArgument(platform);
    if (!appliesTo(normalized)) return null;
    return PlatformRelease._(
      platform: normalized,
      version: version,
      title: title,
      date: date,
      changes: List.unmodifiable(
        changes.where((change) => change.appliesTo(normalized)),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChangelogRelease &&
      other.version == version &&
      other.platform == platform &&
      other.title == title &&
      other.date == date &&
      _listEquals(other.changes, changes);

  @override
  int get hashCode =>
      Object.hash(version, platform, title, date, Object.hashAll(changes));

  @override
  String toString() =>
      'ChangelogRelease($label, "$title", ${changes.length} changes)';

  static String _checkTitle(String? title, int? line) {
    if (title == null) return defaultTitle;
    final String trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ChangelogFormatException(
        'A release title cannot be empty. Omit it to use "$defaultTitle".',
        line: line,
      );
    }
    return trimmed;
  }
}

/// A release filtered for a single [platform]: the notes that platform's
/// users should see.
class PlatformRelease {
  PlatformRelease._({
    required this.platform,
    required this.version,
    required this.title,
    required this.date,
    required this.changes,
  });

  /// The platform these notes are for, such as `ios`.
  final String platform;

  /// The release's version on [platform].
  final AppVersion version;

  /// The release title.
  final String title;

  /// The release date on [platform], or `null` if none was given.
  final DateTime? date;

  /// The changes to display on [platform], in source order, without platform
  /// prefixes.
  final List<ChangelogChange> changes;

  /// The display text of each change in [changes].
  List<String> get notes => [for (final change in changes) change.text];

  /// Whether there are no changes to display on [platform].
  bool get isEmpty => changes.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is PlatformRelease &&
      other.platform == platform &&
      other.version == version &&
      other.title == title &&
      other.date == date &&
      _listEquals(other.changes, changes);

  @override
  int get hashCode =>
      Object.hash(platform, version, title, date, Object.hashAll(changes));

  @override
  String toString() =>
      'PlatformRelease($platform $version, "$title", $changes)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
