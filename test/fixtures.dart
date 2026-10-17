import 'package:app_changelog/src/app_changelog.dart';
import 'package:app_changelog/src/changelog_release.dart';

export 'package:app_changelog/src/app_changelog.dart'
    show changelogFromReleases;
export 'package:app_changelog/src/changelog_release.dart' show ChangelogRelease;

/// Exposes the internal, unfiltered releases to tests.
extension AppChangelogInternals on AppChangelog {
  List<ChangelogRelease> get releases => releasesOf(this);
}

/// The Markdown changelog from the package documentation.
const markdownChangelog = '''
# Changelog

All notable changes to the app are documented here.

## 4.0.0

- Major fixes
- Fix firebase
- Bug fixes and improvements

## 3.12.1

### What's new
- Fix firebase
- Bug fixes and improvements

## 2.9.0

### What's new
- @ios: iPad pencil support
- A brand-new welcome screen
- A new language picker with search
- Improved translations
- @android: Accessibility improvements
- Bug fixes and improvements

## @ios: 2.11.1

- Bug fixes and improvements

## @android: 2.10.1

- Bug fixes and improvements
''';
