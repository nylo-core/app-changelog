## 1.0.0

- Initial release.
- Markdown `CHANGELOG.md` parsing with shared releases (`## 1.2.3`), platform-specific releases (`## @ios: 1.2.3`), optional `###` titles, and platform-specific changes (`- @ios: ...`).
- `AppChangelog.find`, `latestFor`, and `releasesFor` return notes already filtered for a platform.
- `AppChangelog.load()` reads `CHANGELOG.md` by default (override with `path:`), from the asset bundle in a Flutter app or the file system in a `dart run` script.
- Static helpers: `AppChangelog.currentRelease()` returns the installed version's notes for the current platform in one call, `AppChangelog.latestRelease()` the newest release, and `AppChangelog.currentPlatform` the running platform. The installed version is read with `package_info_plus`, so apps don't need to add it themselves.
- Semantic version ordering with pre-release support.
- Validation for duplicate and ambiguous releases, mismatched platform scopes, and malformed input, with line numbers in error messages.
