import 'changelog_change.dart';
import 'changelog_exception.dart';
import 'changelog_release.dart';
import 'platform.dart';
import 'version_comparator.dart';

final _lineSplitPattern = RegExp(r'\r\n?|\n');
final _headingPattern = RegExp(r'^(#{1,6})(?:[ \t]+(.*))?$');
final _listItemPattern = RegExp(r'^[-*+](?:[ \t]+(.*))?$');
final _platformHeadingPattern = RegExp(r'^@([^\s:]*)\s*:\s*(.*)$');
final _datedVersionPattern = RegExp(r'^(\S+)\s+[-–—]\s*(.*)$');
final _isoDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _commentPattern = RegExp(r'^<!--.*-->$');

/// Parses a Markdown changelog into releases, in source order.
///
/// Everything before the first `##` heading (such as a `# Changelog` title
/// or an introduction) is ignored. Inside a release, only an optional
/// `### Title`, list items, indented continuation lines, blank lines and
/// single-line HTML comments are allowed.
///
/// Platform-specific headings stacked with nothing but blank lines between
/// them, such as `## @android: 1.2.1` followed by `## @ios: 1.0.1`, share the
/// title and changes below them, producing one release per heading.
List<ChangelogRelease> parseMarkdownReleases(String source) {
  final releases = <ChangelogRelease>[];
  _ReleaseDraft? draft;

  final List<String> lines =
      source.replaceFirst('﻿', '').split(_lineSplitPattern);
  for (var i = 0; i < lines.length; i++) {
    final int lineNumber = i + 1;
    final String raw = lines[i].trimRight();
    final String trimmed = raw.trimLeft();
    if (trimmed.isEmpty || _commentPattern.hasMatch(trimmed)) continue;
    final isIndented = raw.length != trimmed.length;

    final RegExpMatch? heading =
        isIndented ? null : _headingPattern.firstMatch(trimmed);
    if (heading != null) {
      final int level = heading[1]!.length;
      final String text = heading[2]?.trim() ?? '';
      if (level == 2) {
        final _ReleaseHeading next = _parseReleaseHeading(text, lineNumber);
        if (draft != null && draft.canStack(next)) {
          draft.stack(next);
        } else {
          if (draft != null) releases.addAll(draft.build());
          draft = _ReleaseDraft(next);
        }
      } else if (draft == null) {
        // Preamble before the first release, such as "# Changelog".
      } else if (level == 3) {
        draft.setTitle(text, lineNumber);
      } else {
        throw ChangelogFormatException(
          'Unsupported heading "$trimmed" in release "${draft.heading}". Use '
          '"## <version>" to start a release and "### <title>" for an '
          'optional release title.',
          line: lineNumber,
        );
      }
      continue;
    }

    if (draft == null) continue;

    final RegExpMatch? item =
        isIndented ? null : _listItemPattern.firstMatch(trimmed);
    if (item != null) {
      draft.addChange(item[1] ?? '', lineNumber);
    } else if (isIndented && draft.hasChanges) {
      if (_listItemPattern.hasMatch(trimmed)) {
        throw ChangelogFormatException(
          'Nested lists are not supported in release "${draft.heading}". '
          'Write each change as a top-level "- " list item.',
          line: lineNumber,
        );
      }
      draft.continueChange(trimmed);
    } else {
      throw ChangelogFormatException(
        'Unexpected content in release "${draft.heading}": "$trimmed". '
        'Changes must be list items starting with "- ".',
        line: lineNumber,
      );
    }
  }

  if (draft != null) releases.addAll(draft.build());
  return releases;
}

typedef _ReleaseHeading = ({
  int line,
  String text,
  String? platform,
  AppVersion version,
  DateTime? date,
});

_ReleaseHeading _parseReleaseHeading(String text, int line) {
  if (text.isEmpty) {
    throw ChangelogFormatException(
      'Release heading "##" is missing a version, for example "## 1.2.3" or '
      '"## @ios: 1.2.3".',
      line: line,
    );
  }

  String? platform;
  var versionText = text;
  if (text.startsWith('@')) {
    final RegExpMatch? match = _platformHeadingPattern.firstMatch(text);
    if (match == null) {
      throw ChangelogFormatException(
        'Invalid platform release heading "## $text". Expected '
        '"## @platform: version", for example "## @ios: 2.11.1".',
        line: line,
      );
    }
    platform = normalizePlatform(match[1]!, line: line);
    versionText = match[2]!.trim();
    if (versionText.isEmpty) {
      throw ChangelogFormatException(
        'Release heading "## $text" is missing a version, for example '
        '"## @$platform: 1.2.3".',
        line: line,
      );
    }
  }

  DateTime? date;
  if (_datedVersionPattern.firstMatch(versionText) case final match?) {
    versionText = match[1]!;
    date = _parseReleaseDate(match[2]!.trim(), text, line);
  }

  final AppVersion? version = AppVersion.tryParse(versionText);
  if (version == null) {
    throw ChangelogFormatException(
      'Invalid version "$versionText" in release heading "## $text". '
      'Versions must follow semantic versioning, for example "1.2.3" or '
      '"2.0.0-beta.1".',
      line: line,
    );
  }
  return (
    line: line,
    text: text,
    platform: platform,
    version: version,
    date: date,
  );
}

/// Parses the `YYYY-MM-DD` [text] of a dated release [heading], as a date at
/// midnight UTC.
DateTime _parseReleaseDate(String text, String heading, int line) {
  if (_isoDatePattern.firstMatch(text) case final match?) {
    final int year = int.parse(match[1]!);
    final int month = int.parse(match[2]!);
    final int day = int.parse(match[3]!);
    final date = DateTime.utc(year, month, day);
    // DateTime rolls invalid dates over, so 2024-02-30 becomes March 1st.
    if (date.month == month && date.day == day) return date;
  }
  throw ChangelogFormatException(
    'Invalid date "$text" in release heading "## $heading". Dates must be '
    'written as YYYY-MM-DD, for example "## 1.2.3 - 2024-01-31".',
    line: line,
  );
}

/// A release being assembled while its lines are read.
///
/// A draft has one heading, or several stacked platform-specific headings
/// that share its title and changes.
class _ReleaseDraft {
  _ReleaseDraft(_ReleaseHeading heading) : _headings = [heading];

  final List<_ReleaseHeading> _headings;
  final _changes = <({StringBuffer text, int line})>[];
  String? _title;

  /// The heading text, such as `2.9.0` or `@android: 1.2.1, @ios: 1.0.1`.
  String get heading => _headings.map((heading) => heading.text).join(', ');

  bool get hasChanges => _changes.isNotEmpty;

  /// Whether [next] stacks onto this draft instead of starting a new
  /// release: both are platform-specific and nothing came between them.
  bool canStack(_ReleaseHeading next) =>
      _title == null &&
      !hasChanges &&
      next.platform != null &&
      _headings.every((heading) => heading.platform != null);

  void stack(_ReleaseHeading next) {
    for (final _ReleaseHeading heading in _headings) {
      if (heading.platform == next.platform) {
        throw ChangelogFormatException(
          'Release heading "## ${next.text}" repeats the platform '
          '"${next.platform}" of "## ${heading.text}" (line ${heading.line}). '
          'Stacked headings share the changes below them, so each platform '
          'can appear only once. Add changes under "## ${heading.text}" or '
          'remove it.',
          line: next.line,
        );
      }
    }
    _headings.add(next);
  }

  void setTitle(String text, int line) {
    if (_title != null) {
      throw ChangelogFormatException(
        'Release "$heading" already has the title "$_title". Only one '
        '"###" title is allowed per release.',
        line: line,
      );
    }
    if (hasChanges) {
      throw ChangelogFormatException(
        'The title "### $text" must come before the changes of release '
        '"$heading".',
        line: line,
      );
    }
    if (text.isEmpty) {
      throw ChangelogFormatException(
        'The "###" title of release "$heading" is empty. Remove it to use '
        '"${ChangelogRelease.defaultTitle}".',
        line: line,
      );
    }
    _title = text;
  }

  void addChange(String text, int line) =>
      _changes.add((text: StringBuffer(text), line: line));

  void continueChange(String text) => _changes.last.text.write(' $text');

  /// Builds one release per heading.
  List<ChangelogRelease> build() {
    final List<ChangelogChange> changes = [
      for (final change in _changes)
        parseChange(change.text.toString(), line: change.line),
    ];
    if (_headings.length == 1) {
      final _ReleaseHeading heading = _headings.single;
      return [
        ChangelogRelease(
          heading.version,
          platform: heading.platform,
          title: _title,
          date: heading.date,
          changes: changes,
          line: heading.line,
        ),
      ];
    }

    final List<String> platforms = [
      for (final heading in _headings) heading.platform!,
    ];
    for (var i = 0; i < changes.length; i++) {
      final ChangelogChange change = changes[i];
      if (change.platform case final platform?
          when !platforms.contains(platform)) {
        throw ChangelogFormatException(
          'The change "@$platform: ${change.text}" targets "$platform", but '
          'release "$heading" only applies to ${_joinPlatforms(platforms)}. '
          'Remove the "@" prefix or move the change to a release for '
          '"$platform".',
          line: _changes[i].line,
        );
      }
    }
    return [
      for (final heading in _headings)
        ChangelogRelease(
          heading.version,
          platform: heading.platform,
          title: _title,
          date: heading.date,
          changes: [
            for (final change in changes)
              if (change.appliesTo(heading.platform!)) change,
          ],
          line: heading.line,
        ),
    ];
  }
}

/// Joins [platforms] for a message, such as `android, ios and web`.
String _joinPlatforms(List<String> platforms) => platforms.length == 1
    ? platforms.single
    : '${platforms.sublist(0, platforms.length - 1).join(', ')} and '
        '${platforms.last}';
