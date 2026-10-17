import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the changelog bundled as the asset at [path].
Future<String> readChangelog(String path) => rootBundle.loadString(path);

/// The platform the app is running on: `web`, `ios`, `android`, `macos`,
/// `windows`, `linux` or `fuchsia`.
String get runningPlatform =>
    kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

/// The installed app version, read with `package_info_plus`.
Future<String> installedVersion() async =>
    (await PackageInfo.fromPlatform()).version;

/// The value stored under [key] with `shared_preferences`, or `null` if
/// nothing is stored.
Future<String?> readStoredValue(String key) async =>
    (await SharedPreferences.getInstance()).getString(key);

/// Stores [value] under [key] with `shared_preferences`.
Future<void> writeStoredValue(String key, String value) async {
  await (await SharedPreferences.getInstance()).setString(key, value);
}
