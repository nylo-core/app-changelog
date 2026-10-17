import 'changelog_exception.dart';

final _platformPattern = RegExp(r'^[a-z][a-z0-9_-]*$');

/// Returns [platform] trimmed and lowercased, or `null` if it is not a valid
/// platform identifier.
String? tryNormalizePlatform(String platform) {
  final String normalized = platform.trim().toLowerCase();
  return _platformPattern.hasMatch(normalized) ? normalized : null;
}

/// Normalizes a platform identifier read from a changelog, throwing a
/// [ChangelogFormatException] if it is invalid.
String normalizePlatform(String platform, {int? line}) {
  final String? normalized = tryNormalizePlatform(platform);
  if (normalized == null) {
    throw ChangelogFormatException(
      'Invalid platform identifier "$platform". Platform identifiers must '
      'start with a letter and contain only letters, digits, "_" or "-", '
      'for example "ios", "android" or "web".',
      line: line,
    );
  }
  return normalized;
}

/// Normalizes a platform identifier passed to a query method, throwing an
/// [ArgumentError] if it is invalid.
String checkPlatformArgument(String platform) {
  final String? normalized = tryNormalizePlatform(platform);
  if (normalized == null) {
    throw ArgumentError.value(
      platform,
      'platform',
      'Must start with a letter and contain only letters, digits, "_" or "-"',
    );
  }
  return normalized;
}
