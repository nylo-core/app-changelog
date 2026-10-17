import 'changelog_change.dart';
import 'changelog_exception.dart';
import 'changelog_release.dart';
import 'platform.dart';
import 'version_comparator.dart';

final _lineSplitPattern = RegExp(r'\r\n?|\n');
final _headingPattern = RegExp(r'^(#{1,6})(?:[ \t]+(.*))?$');
final _listItemPattern = RegExp(r'^[-*+](?:[ \t]+(.*))?$');
final _platformHeadingPattern = RegExp(r'^@([^\s:]*)\s*:\s*(.*)$');
final _commentPattern = RegExp(r'^<!--.*-->$');

/// Parses a Markdown changelog into releases, in source order.
///
/// Everything before the first `##` heading (such as a `# Changelog` title
/// or an introduction) is ignored. Inside a release, only an optional
/// `### Title`, list items, indented continuation lines, blank lines and
/// single-line HTML comments are allowed.
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
        if (draft != null) releases.add(draft.build());
        draft = _parseReleaseHeading(text, lineNumber);
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

  if (draft != null) releases.add(draft.build());
  return releases;
}

_ReleaseDraft _parseReleaseHeading(String text, int line) {
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

  final AppVersion? version = AppVersion.tryParse(versionText);
  if (version == null) {
    throw ChangelogFormatException(
      'Invalid version "$versionText" in release heading "## $text". '
      'Versions must follow semantic versioning, for example "1.2.3" or '
      '"2.0.0-beta.1".',
      line: line,
    );
  }
  return _ReleaseDraft(line, text, platform, version);
}

/// A release being assembled while its lines are read.
class _ReleaseDraft {
  _ReleaseDraft(this.line, this.heading, this.platform, this.version);

  final int line;
  final String heading;
  final String? platform;
  final AppVersion version;
  final _changes = <({StringBuffer text, int line})>[];
  String? _title;

  bool get hasChanges => _changes.isNotEmpty;

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

  ChangelogRelease build() {
    final List<ChangelogChange> changes = [
      for (final change in _changes)
        parseChange(change.text.toString(), line: change.line),
    ];
    return ChangelogRelease(
      version,
      platform: platform,
      title: _title,
      changes: changes,
      line: line,
    );
  }
}
