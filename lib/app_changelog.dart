/// One changelog. Every platform.
///
/// A platform-aware changelog parser for app release notes that supports
/// shared releases, platform-specific releases and platform-specific changes
/// within a shared release.
///
/// ```dart
/// import 'package:app_changelog/app_changelog.dart';
///
/// final release = await AppChangelog.currentRelease();
/// print(release?.title);
/// print(release?.notes);
/// ```
///
/// The same import works outside a Flutter app, such as in a CI/CD script run
/// with `dart run`, where [AppChangelog.load] reads from the file system.
library;

export 'src/app_changelog.dart' show AppChangelog;
export 'src/changelog_change.dart' show ChangelogChange;
export 'src/changelog_exception.dart' show ChangelogFormatException;
export 'src/changelog_release.dart' show PlatformRelease;
export 'src/version_comparator.dart' show AppVersion;
