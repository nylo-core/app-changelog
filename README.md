# app_changelog

**One changelog. Every platform.**

`app_changelog` is a lightweight, platform-aware changelog parser for app
release notes. Keep the notes for iOS, Android, and any other platform in one
`CHANGELOG.md`. It handles:

- **shared releases** that apply to every platform,
- **platform-specific releases**, such as an iOS-only hotfix, and
- **platform-specific changes** inside a shared release.

It's built for Flutter apps. It reads the changelog asset, the installed
version and the current platform for you, so showing "What's new" takes one
call. The same changelog can also drive your CI/CD pipeline.

```markdown
## 2.9.0

### What's new
- @ios: iPad pencil support
- A brand-new welcome screen
- @android: Accessibility improvements
- Bug fixes and improvements

## @ios: 2.11.1

- Bug fixes and improvements
```

```dart
// On Android, with version 2.9.0 installed:
final release = await AppChangelog.currentRelease();

print(release?.title); // What's new
print(release?.notes);
// [A brand-new welcome screen, Accessibility improvements, Bug fixes and improvements]
```

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Tracking updates](#tracking-updates)
- [Markdown format](#markdown-format)
- [Querying a changelog](#querying-a-changelog)
- [CI/CD integration](#cicd-integration)
- [API overview](#api-overview)
- [Errors](#errors)
- [Limitations](#limitations)

## Installation

```sh
flutter pub add app_changelog
```

That's the only dependency you need. `app_changelog` uses
[`package_info_plus`](https://pub.dev/packages/package_info_plus) internally
to read the installed version, and
[`shared_preferences`](https://pub.dev/packages/shared_preferences) to
remember the last version a user has seen, so you don't have to add either
yourself.

## Quick start

**1. Bundle `CHANGELOG.md` as an asset** in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - CHANGELOG.md
```

**2. Load the notes for the installed version:**

```dart
import 'package:app_changelog/app_changelog.dart';

final release = await AppChangelog.currentRelease();
```

`AppChangelog.currentRelease()` reads `CHANGELOG.md`, the installed version (with
`package_info_plus`) and the current platform, and returns that version's
notes filtered for the platform. It returns `null` if the changelog has no
release for the installed version on this platform.

If your changelog lives somewhere else, pass its asset path:

```dart
final release = await AppChangelog.currentRelease(
  path: 'assets/release_notes.md',
);
```

**3. Display the title and notes:**

```dart
Future<void> showWhatsNew(BuildContext context) async {
  final release = await AppChangelog.currentRelease();
  if (release == null || release.isEmpty || !context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(release.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final note in release.notes) Text('• $note')],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
```

**4. Show them once per version.** Call `AppChangelog.track()` before
`runApp`, then show the notes when the user has updated:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppChangelog.track();
  runApp(const MyApp());
}
```

```dart
if (AppChangelog.didUpdate) {
  await showWhatsNew(context);
  await AppChangelog.markVersionSeen();
}
```

See [Tracking updates](#tracking-updates) for the details.

## Tracking updates

`AppChangelog.track()` remembers the last version whose notes the user has
seen, so your app can tell a new install from an update. Call it once, before
`runApp`:

```dart
await AppChangelog.track();

AppChangelog.isNewInstall;    // true on the first launch after installing
AppChangelog.didUpdate;       // true when the user has updated since the
                              // last version marked as seen
AppChangelog.previousVersion; // the last version marked as seen, if any

await AppChangelog.markVersionSeen(); // didUpdate is false until the next update
```

- On a new install, `track()` stores the installed version straight away, so
  `didUpdate` is `false` and the notes for the version the user just
  installed aren't shown.
- `didUpdate` stays `true` until you call `markVersionSeen()`. If your app
  can't show the notes on one launch, for example because the user isn't
  signed in, it can show them on the next.
- `markVersionSeen()` never stores a lower version, so downgrades don't bring
  old notes back.
- Build metadata is ignored, so `2.9.1+41` isn't an update from `2.9.1+40`.
- iOS and Android version histories are tracked separately, since each device
  stores its own installed version.

### Showing every release since the last update

A user who jumps from `2.7.0` to `2.9.1` might have missed the notes for
`2.8.0` and `2.9.0`. `unseenReleases()` returns every release on the current
platform above the last version marked as seen, up to the installed version,
newest first:

```dart
final List<PlatformRelease> releases = await AppChangelog.unseenReleases();
for (final release in releases) {
  print('${release.version}: ${release.notes}');
}
```

Releases with no notes for the platform are skipped, and so are
pre-releases unless the installed version is itself a pre-release. The list
is empty when `didUpdate` is `false`.

### Adding tracking to a published app

Existing users have nothing stored yet, so by default they look like new
installs. Pass `isExistingInstall` to tell them apart, using something your
app already stores:

```dart
await AppChangelog.track(
  isExistingInstall: () async => prefs.getBool('onboarding_done') ?? false,
);
```

When it returns `true`, `didUpdate` is `true` and `previousVersion` is `null`.
`unseenReleases()` then returns only the installed version's notes, not the
whole history.

### Storage

The version is stored under the key `app_changelog.seen_version` with
`shared_preferences`. Pass `key` to change it, or `read` and `write` to use
your own storage instead:

```dart
final Box<String> box = await Hive.openBox<String>('settings');

await AppChangelog.track(
  read: (key) async => box.get(key),
  write: (key, value) => box.put(key, value),
);
```

In widget tests, set the stored version with
`SharedPreferences.setMockInitialValues` before calling `track()`.

## Markdown format

> **Note:** `@ios:`, `@android:` and other `@platform:` prefixes are
> conventions defined by `app_changelog`. They aren't part of Markdown, and
> other Markdown renderers (GitHub, pub.dev) show them as plain text.

```markdown
# Changelog

Anything before the first release heading is ignored.

## 4.0.0

- Major fixes
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
```

### Release headings

| Heading                 | Applies to                                  |
| ----------------------- | ------------------------------------------- |
| `## 4.0.0`              | Every platform                              |
| `## @ios: 2.11.1`       | iOS only                                    |
| `## @android: 2.10.1`   | Android only                                |
| `## @web: 1.0.0`        | Any custom platform, e.g. web               |
| `## 4.0.0 - 2024-01-31` | Every platform, released on 31 January 2024 |

- Versions must follow [semantic versioning](https://semver.org), such as
  `1.2.3`, `2.0.0-beta.1`, or `1.2.3+42`.
- Platform identifiers start with a letter and contain letters, digits, `_`,
  or `-`. They're case-insensitive: `@iOS` and `@ios` are the same platform.
- `### Title` directly under a release heading sets an optional title. Without
  one, the title is `"What's new"`.
- An optional release date follows the version after ` - `, written as
  `YYYY-MM-DD`: `## 4.0.0 - 2024-01-31` or `## @ios: 2.11.1 - 2024-02-03`.
  It's available as `date`, a `DateTime` at midnight UTC.

### Shared notes across platform versions

When several platforms ship the same notes under different version numbers,
stack their headings. Platform-specific headings with nothing but blank lines
between them share the title and changes below them:

```markdown
## @android: 1.2.1 - 2024-01-31
## @ios: 1.0.1

- iPad updates
- @android: Some Google stuff
- @ios: Some iOS stuff
```

Android 1.2.1 shows "iPad updates" and "Some Google stuff", and iOS 1.0.1
shows "iPad updates" and "Some iOS stuff". Each heading is its own release, so
each can have its own date, and changes can target any platform in the stack.
Shared headings (`## 1.2.1`) never stack: a shared heading with no changes is
an empty release.

### Changes

Each change is a list item (`-`, `*`, or `+`):

| Change                                  | Shown on                                  |
| --------------------------------------- | ----------------------------------------- |
| `- Bug fixes and improvements`          | Every platform the release applies to     |
| `- @ios: iPad pencil support`           | iOS only                                  |
| `- @android: Accessibility improvements` | Android only                              |

When you request a release for a platform, `app_changelog`:

1. includes every untagged change,
2. includes changes tagged for that platform,
3. excludes changes tagged for other platforms,
4. preserves the original order, and
5. strips the `@platform:` prefix from the displayed text.

A change in a platform-specific release can only target that release's
platform. For example, `- @android: ...` under `## @ios: 2.11.1` is reported
as an error.

You can wrap a long change onto indented continuation lines, which are joined
with a single space. To start a change with a literal `@` followed by a
colon, escape it as `\@`, for example `- \@team: thanks for the reports`. An
`@` that isn't followed by an identifier and a colon, as in
`- @mentions are now supported`, needs no escaping.

Blank lines and single-line HTML comments (`<!-- ... -->`) are ignored.

## Querying a changelog

### Static helpers

Each helper loads the changelog (`CHANGELOG.md`, or `path:`) and answers one
question:

```dart
// The installed version's notes on this platform. Flutter only.
final current = await AppChangelog.currentRelease();

// The newest release on this platform, or on the one you name.
final latest = await AppChangelog.latestRelease();
final latestAndroid = await AppChangelog.latestRelease(platform: 'android');

// The running platform: ios, android, web, macos, windows or linux.
print(AppChangelog.currentPlatform);
```

### Loading the whole changelog

For anything else, load the changelog once and query it. Every query returns
notes already filtered for the platform.

```dart
final changelog = await AppChangelog.load(); // or load(path: '...')

// Notes for a specific version.
final release = changelog.find(platform: 'ios', version: '2.9.0');
print(release?.title);   // What's new
print(release?.version); // 2.9.0
print(release?.notes);   // [iPad pencil support, A brand-new welcome screen, ...]

// Latest release for a platform.
final latest = changelog.latestFor('ios');

// Every release that applies to Android, newest first.
for (final release in changelog.releasesFor('android')) {
  print('${release.version}: ${release.notes}');
}
```

- `find` returns `null` when the platform has no release with that version.
  Build metadata is ignored, so `find(version: '2.9.0+120')` matches `2.9.0`.
- `latestFor` and `latestRelease` return the highest version by semantic
  versioning, regardless of where the release appears in the file. Pass
  `includePreReleases: false` to skip versions such as `3.0.0-beta.1`.
- iOS and Android histories are independent. With `## @ios: 2.11.1` and
  `## @android: 2.10.1`, the latest iOS release is `2.11.1` and the latest
  Android release is `2.10.1`.
- In a Flutter app, `path` is an asset key and must be listed under
  `flutter: assets:`. In a Dart script, it's a file path relative to the
  working directory.

If you already have the Markdown as a string, for example in a test, parse it
with `AppChangelog.parse(markdown)`.

## CI/CD integration

A CI job can read the changelog and use the latest version for each platform
as the Flutter **build name**. Build numbers stay the responsibility of your
CI/CD platform.

Copy [`example/ci_latest_version.dart`](example/ci_latest_version.dart) into
your Flutter project, for example as `tool/latest_version.dart`. It runs with
plain `dart run`, where `AppChangelog.load` reads from the file system
instead of the asset bundle.

```sh
$ dart run tool/latest_version.dart CHANGELOG.md ios
2.11.1

$ dart run tool/latest_version.dart CHANGELOG.md ios android
ios=2.11.1
android=2.10.1
```

The script exits with a non-zero code if the changelog is malformed or a
platform has no stable release, so a broken changelog fails the build.

**GitHub Actions:**

```yaml
- name: Read build names from CHANGELOG.md
  id: versions
  run: dart run tool/latest_version.dart CHANGELOG.md ios android >> "$GITHUB_OUTPUT"

- name: Build iOS
  run: >
    flutter build ipa
    --build-name=${{ steps.versions.outputs.ios }}
    --build-number=${{ github.run_number }}

- name: Build Android
  run: >
    flutter build appbundle
    --build-name=${{ steps.versions.outputs.android }}
    --build-number=${{ github.run_number }}
```

**Any shell-based CI (Codemagic, Bitrise, GitLab CI, ...):**

```sh
BUILD_NAME="$(dart run tool/latest_version.dart CHANGELOG.md android)"
flutter build appbundle --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER"
```

The core of the script is short enough to inline in your own tooling:

```dart
import 'package:app_changelog/app_changelog.dart';

Future<void> main() async {
  for (final platform in ['ios', 'android']) {
    final latest = await AppChangelog.latestRelease(
      platform: platform,
      includePreReleases: false,
    );
    print('$platform=${latest?.version}');
  }
}
```

## API overview

Everything is available from `package:app_changelog/app_changelog.dart`, in
Flutter apps and in scripts run with `dart run`.

**Static helpers.** `path` defaults to `CHANGELOG.md`.

| API                                                          | Description                                                          |
| ------------------------------------------------------------ | -------------------------------------------------------------------- |
| `AppChangelog.load({path})`                                  | Loads and parses the changelog.                                      |
| `AppChangelog.parse(String)`                                 | Parses and validates a Markdown string.                              |
| `AppChangelog.currentRelease({path})`                        | The installed version's notes on this platform, or `null`. Flutter only. |
| `AppChangelog.latestRelease({platform, path, includePreReleases})` | The newest release on `platform` (default: this one), or `null`. |
| `AppChangelog.currentPlatform`                               | The running platform's identifier, such as `ios`.                    |

**Tracking updates.** Call `track()` first. Flutter only.

| API                                                      | Description                                                                 |
| -------------------------------------------------------- | --------------------------------------------------------------------------- |
| `AppChangelog.track({key, read, write, isExistingInstall})` | Reads the last version marked as seen, and records new installs.            |
| `AppChangelog.isNewInstall`                              | Whether this is the first launch since the app was installed.               |
| `AppChangelog.didUpdate`                                 | Whether the installed version is newer than the last version marked as seen. |
| `AppChangelog.previousVersion`                           | The last version marked as seen before this launch, or `null`.              |
| `AppChangelog.markVersionSeen()`                         | Stores the installed version as seen.                                       |
| `AppChangelog.unseenReleases({path})`                    | Releases since the last version marked as seen, newest first.               |

**Queries on a loaded changelog.**

| API                                                   | Description                                                        |
| ----------------------------------------------------- | ------------------------------------------------------------------ |
| `changelog.find(platform:, version:)`                 | The release at that version, filtered for the platform, or `null`. |
| `changelog.latestFor(platform, {includePreReleases})` | The highest-version release for the platform, or `null`.           |
| `changelog.releasesFor(platform)`                     | All releases for the platform, filtered, newest first.             |
| `changelog.platforms`                                 | Platforms named explicitly in the changelog.                       |

**`PlatformRelease`** is a release filtered for one platform, as returned by
every query:

| Member     | Description                                                     |
| ---------- | --------------------------------------------------------------- |
| `platform` | The platform the notes are for, such as `ios`.                  |
| `version`  | The release's version on that platform (`AppVersion`).          |
| `title`    | The release title, `"What's new"` by default.                   |
| `date`     | The release date on that platform (`DateTime?`).                |
| `changes`  | The filtered `List<ChangelogChange>`, in source order.          |
| `notes`    | The changes' display text as a `List<String>`.                  |
| `isEmpty`  | Whether the platform has no changes to show.                    |

**`ChangelogChange`** has the display `text` and the targeted `platform`
(`null` when shared). Its `toString()` returns the text, so a list of changes
prints readably.

**`AppVersion`** is a semantic version with `major`, `minor`, `patch`,
`preRelease`, `build`, and `isPreRelease`. It's `Comparable` and supports `<`,
`<=`, `>`, and `>=`.

All models are immutable. Their lists and maps are unmodifiable, and they
implement value equality.

## Errors

Malformed changelogs throw a `ChangelogFormatException` (a
`FormatException`) that describes the problem and includes the 1-based line
number where it was found:

```text
ChangelogFormatException: Line 12: Invalid version "2.9" in release heading "## 2.9". Versions must follow semantic versioning, for example "1.2.3" or "2.0.0-beta.1".
ChangelogFormatException: Line 20: The change "@android: Wrong" targets "android", but release "@ios: 2.11.1" only applies to ios. Remove the "@" prefix or move the change to a release for "android".
ChangelogFormatException: Line 31: Ambiguous release 2.9.0: a shared release and a platform-specific release cannot have the same version. ...
```

Validation covers:

- invalid versions and platform identifiers,
- invalid release dates,
- changes that target a platform outside their release,
- a platform repeated in stacked headings,
- empty changes and empty titles,
- duplicate releases for the same platform and version,
- a shared release and a platform-specific release with the same version, and
- unexpected Markdown content.

Query methods throw an `ArgumentError` for an invalid platform identifier, and
`find` throws a `FormatException` for an invalid version. Using
`isNewInstall`, `didUpdate`, `previousVersion`, `markVersionSeen` or
`unseenReleases` before `AppChangelog.track()` throws a `StateError`.

## Limitations

- **One title per release.** Keep a Changelog–style sections (`### Added`,
  `### Fixed`) aren't supported, and nested lists are rejected.
- **Strict headings.** `## Unreleased`, `## [1.2.0] - 2024-01-01`, and
  `## v1.2.0` aren't valid release headings. Headings must be exactly
  `## <version>` or `## @platform: <version>`, optionally followed by
  ` - YYYY-MM-DD`.
- **One platform per change or heading.** A release is either shared or for a
  single platform. To give several, but not all, platforms the same notes,
  [stack their headings](#shared-notes-across-platform-versions).
- **Plain text.** Change text is returned exactly as written. Inline Markdown
  such as `**bold**` or links isn't rendered or stripped.
- **Semantic versions only.** Two-part versions such as `2.9` are rejected.
  Build metadata (`+42`) is ignored when comparing versions, so `1.0.0+1` and
  `1.0.0+2` count as the same release.
- **Flutter projects only.** The package depends on the Flutter SDK, so a
  pure Dart project (a server or a standalone CLI) can't add it. Scripts
  inside a Flutter project can still use it with `dart run`.
- **No UI.** The package returns notes but doesn't display them. See
  [Quick start](#quick-start) for a dialog you can adapt.

## License

MIT. See [LICENSE](LICENSE).
