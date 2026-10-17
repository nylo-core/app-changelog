final _semverPattern = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)'
  r'(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?'
  r'(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$',
);

final _numericPattern = RegExp(r'^\d+$');

/// A semantic version (see https://semver.org) identifying an app release.
///
/// Versions are ordered by semantic versioning precedence rather than by
/// string order, so `2.10.0 > 2.9.0` and `3.0.0-beta.2 < 3.0.0`.
///
/// Build metadata (the `+42` in `1.2.3+42`) is preserved by [toString] but,
/// as the specification requires, ignored by comparison and equality.
class AppVersion implements Comparable<AppVersion> {
  AppVersion._(this.major, this.minor, this.patch, this.preRelease, this.build);

  /// Parses a semantic version such as `1.2.3`, `2.0.0-beta.1` or
  /// `1.2.3+42`.
  ///
  /// Throws a [FormatException] if [version] is not a valid semantic version.
  factory AppVersion.parse(String version) {
    final AppVersion? parsed = tryParse(version);
    if (parsed == null) {
      throw FormatException(
        'Invalid version "$version". Versions must follow semantic '
        'versioning, for example "1.2.3" or "2.0.0-beta.1".',
        version,
      );
    }
    return parsed;
  }

  /// Parses [version] like [AppVersion.parse], returning `null` instead of
  /// throwing when it is invalid.
  static AppVersion? tryParse(String version) {
    final RegExpMatch? match = _semverPattern.firstMatch(version.trim());
    final int? major = int.tryParse(match?[1] ?? '');
    final int? minor = int.tryParse(match?[2] ?? '');
    final int? patch = int.tryParse(match?[3] ?? '');
    if (match == null || major == null || minor == null || patch == null) {
      return null;
    }
    return AppVersion._(
      major,
      minor,
      patch,
      List.unmodifiable(match[4]?.split('.') ?? const <String>[]),
      match[5],
    );
  }

  /// The major version number.
  final int major;

  /// The minor version number.
  final int minor;

  /// The patch version number.
  final int patch;

  /// The dot-separated pre-release identifiers, such as `['beta', '1']` for
  /// `2.0.0-beta.1`. Empty for stable versions.
  final List<String> preRelease;

  /// The build metadata, such as `42` for `1.2.3+42`, or `null`.
  final String? build;

  /// Whether this is a pre-release version, such as `2.0.0-beta.1`.
  bool get isPreRelease => preRelease.isNotEmpty;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // A stable version has higher precedence than any of its pre-releases.
    if (!isPreRelease) return other.isPreRelease ? 1 : 0;
    if (!other.isPreRelease) return -1;

    final int length = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var i = 0; i < length; i++) {
      final int result =
          _compareIdentifiers(preRelease[i], other.preRelease[i]);
      if (result != 0) return result;
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }

  /// Whether this version has lower precedence than [other].
  bool operator <(AppVersion other) => compareTo(other) < 0;

  /// Whether this version has lower or equal precedence to [other].
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  /// Whether this version has higher precedence than [other].
  bool operator >(AppVersion other) => compareTo(other) > 0;

  /// Whether this version has higher or equal precedence to [other].
  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  /// Two versions are equal when they have the same precedence; build
  /// metadata is ignored.
  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode =>
      Object.hash(major, minor, patch, Object.hashAll(preRelease));

  @override
  String toString() {
    final buffer = StringBuffer('$major.$minor.$patch');
    if (isPreRelease) buffer.write('-${preRelease.join('.')}');
    if (build != null) buffer.write('+$build');
    return buffer.toString();
  }
}

/// Compares two pre-release identifiers using semantic versioning rules:
/// numeric identifiers compare numerically and sort before alphanumeric ones.
int _compareIdentifiers(String a, String b) {
  final bool aNumeric = _numericPattern.hasMatch(a);
  final bool bNumeric = _numericPattern.hasMatch(b);
  if (aNumeric && bNumeric) {
    // Numeric identifiers have no leading zeros, so a longer one is larger.
    // Comparing this way avoids overflow on very large numbers.
    if (a.length != b.length) return a.length.compareTo(b.length);
    return a.compareTo(b);
  }
  if (aNumeric) return -1;
  if (bNumeric) return 1;
  return a.compareTo(b);
}
