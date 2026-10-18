## 1.2.0

- `dart run app_changelog version` prints the newest version in `CHANGELOG.md`, ready for `flutter build --build-name`. Pass `--platform ios` for one platform or `--platform ios,android` for `platform=version` lines. Without `--platform`, it reads the project's platform folders.
- `dart run app_changelog check` fails a release when the changelog can't be parsed, a platform has no release or no notes, or `pubspec.yaml` is ahead of the changelog. It warns when `Info.plist` doesn't read `$(FLUTTER_BUILD_NAME)`, since `--build-name` then won't change the iOS or macOS version.
- Both commands skip pre-releases unless `--pre-releases` is passed, and read another changelog with `--path`.
- The README's CI/CD section uses the new commands. `example/ci_latest_version.dart` is removed, since `version` replaces it.

## 1.1.0

- `AppChangelog.track()` remembers the last version whose release notes the user has seen, stored with `shared_preferences`. Call it once before `runApp`.
- `AppChangelog.isNewInstall` and `AppChangelog.didUpdate` tell a new install from an update, and `AppChangelog.previousVersion` returns the last version marked as seen.
- `AppChangelog.markVersionSeen()` stores the installed version as seen. It never stores a lower version.
- `AppChangelog.unseenReleases()` returns every release since the last version marked as seen, so users who skip versions see everything they missed.
- `isExistingInstall` lets apps that add tracking after launch count current users as updated, and `read`/`write` replace `shared_preferences` with your own storage.

## 1.0.0

- Initial release.
- Markdown `CHANGELOG.md` parsing with shared releases (`## 1.2.3`), platform-specific releases (`## @ios: 1.2.3`), optional `###` titles, and platform-specific changes (`- @ios: ...`).
- Optional release dates in headings (`## 1.2.3 - 2024-01-31`), exposed as `date`.
- Stacked platform headings (`## @android: 1.2.1` followed by `## @ios: 1.0.1`) that share one set of notes across different platform versions.
- `AppChangelog.find`, `latestFor`, and `releasesFor` return notes already filtered for a platform.
- `AppChangelog.load()` reads `CHANGELOG.md` by default (override with `path:`), from the asset bundle in a Flutter app or the file system in a `dart run` script.
- Static helpers: `AppChangelog.currentRelease()` returns the installed version's notes for the current platform in one call, `AppChangelog.latestRelease()` the newest release, and `AppChangelog.currentPlatform` the running platform. The installed version is read with `package_info_plus`, so apps don't need to add it themselves.
- Semantic version ordering with pre-release support.
- Validation for duplicate and ambiguous releases, mismatched platform scopes, and malformed input, with line numbers in error messages.
