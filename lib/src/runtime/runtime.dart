// The runtime used when neither Flutter nor dart:io is available.
//
// `app_changelog.dart` imports this file conditionally, replacing it with
// `runtime_flutter.dart` in a Flutter app and `runtime_io.dart` in a Dart
// script, so the package works in both without separate entry points.

/// Reads the changelog at [path].
Future<String> readChangelog(String path) =>
    throw UnsupportedError('Loading a changelog is not supported here.');

/// The platform the code is running on, as a changelog platform identifier.
String get runningPlatform =>
    throw UnsupportedError('The current platform is unknown here.');

/// The installed app version, such as `2.9.0`.
Future<String> installedVersion() =>
    throw UnsupportedError('The installed version is unknown here.');
