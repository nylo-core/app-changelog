import 'changelog_exception.dart';
import 'platform.dart';

final _platformTagPattern = RegExp(r'^@([^\s:]*)\s*:\s*(.*)$', dotAll: true);
final _lineBreakPattern = RegExp(r'\s*\n\s*');

/// A single entry in a release's notes, such as "Bug fixes and improvements".
///
/// A change either applies to every platform its release covers
/// ([isShared]), or targets a single [platform]. Platform targeting is kept
/// as structured data and is never part of [text].
class ChangelogChange {
  /// Creates a change with display [text], optionally targeting a single
  /// [platform].
  ///
  /// [platform] is normalized to lowercase. Throws a
  /// [ChangelogFormatException] if [text] is empty or [platform] is not a
  /// valid platform identifier.
  factory ChangelogChange(String text, {String? platform}) {
    final String normalizedText = _normalizeText(text);
    if (normalizedText.isEmpty) {
      throw const ChangelogFormatException('A change cannot be empty.');
    }
    return ChangelogChange._(
      normalizedText,
      platform == null ? null : normalizePlatform(platform),
    );
  }

  const ChangelogChange._(this.text, this.platform);

  /// Parses a change written in app_changelog notation.
  ///
  /// `"@ios: iPad pencil support"` targets iOS, while
  /// `"Bug fixes and improvements"` applies to every platform. Start the text
  /// with `\@` to keep a leading `@` literally.
  factory ChangelogChange.parse(String source) => parseChange(source);

  /// The text to display, without any platform prefix.
  final String text;

  /// The platform this change targets, or `null` if it applies to every
  /// platform covered by its release.
  final String? platform;

  /// Whether this change applies to every platform covered by its release.
  bool get isShared => platform == null;

  /// Whether this change should be shown on [platform].
  bool appliesTo(String platform) =>
      isShared || this.platform == (tryNormalizePlatform(platform) ?? platform);

  @override
  bool operator ==(Object other) =>
      other is ChangelogChange &&
      other.text == text &&
      other.platform == platform;

  @override
  int get hashCode => Object.hash(text, platform);

  /// Returns the display [text], so a list of changes prints readably.
  @override
  String toString() => text;
}

/// Parses a change written in app_changelog notation, reporting errors
/// against the 1-based source [line] when given.
ChangelogChange parseChange(String source, {int? line}) {
  final String text = _normalizeText(source);
  if (text.isEmpty) {
    throw ChangelogFormatException('A change cannot be empty.', line: line);
  }
  if (text.startsWith(r'\@')) return ChangelogChange._(text.substring(1), null);

  final RegExpMatch? match = _platformTagPattern.firstMatch(text);
  if (match == null) return ChangelogChange._(text, null);

  final String platform = normalizePlatform(match[1]!, line: line);
  final String body = match[2]!.trim();
  if (body.isEmpty) {
    throw ChangelogFormatException(
      'The change "$text" targets "@$platform" but has no text.',
      line: line,
    );
  }
  return ChangelogChange._(body, platform);
}

/// Trims [text] and joins wrapped lines with single spaces.
String _normalizeText(String text) =>
    text.trim().replaceAll(_lineBreakPattern, ' ');
