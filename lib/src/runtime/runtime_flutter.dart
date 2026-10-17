import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Reads the changelog bundled as the asset at [path].
Future<String> readChangelog(String path) => rootBundle.loadString(path);

/// The platform the app is running on: `web`, `ios`, `android`, `macos`,
/// `windows`, `linux` or `fuchsia`.
String get runningPlatform =>
    kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

/// The installed app version, read with `package_info_plus`.
Future<String> installedVersion() async =>
    (await PackageInfo.fromPlatform()).version;
