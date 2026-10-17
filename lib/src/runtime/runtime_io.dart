import 'dart:io';

/// Reads the changelog file at [path], relative to the working directory.
Future<String> readChangelog(String path) => File(path).readAsString();

/// The operating system the script is running on, such as `macos`.
String get runningPlatform => Platform.operatingSystem;

/// Throws, since a Dart script has no installed app version.
Future<String> installedVersion() => throw UnsupportedError(
      'The installed app version is only available in a Flutter app. Use '
      'find(platform: ..., version: ...) instead.',
    );

/// Throws, since a Dart script has no app storage.
Future<String?> readStoredValue(String key) => throw UnsupportedError(
      'Tracking seen versions is only available in a Flutter app.',
    );

/// Throws, since a Dart script has no app storage.
Future<void> writeStoredValue(String key, String value) =>
    throw UnsupportedError(
      'Tracking seen versions is only available in a Flutter app.',
    );
