/// Thrown when a changelog cannot be parsed or fails validation.
///
/// This is a [FormatException], so existing `on FormatException` handlers
/// also catch it.
class ChangelogFormatException extends FormatException {
  /// Creates an exception describing a problem with a changelog.
  ///
  /// [line] is the 1-based line in the changelog source where the problem
  /// was found, when known.
  const ChangelogFormatException(super.message, {this.line});

  /// The 1-based line in the changelog source where the problem was found,
  /// or `null` when the location is unknown.
  final int? line;

  @override
  String toString() => line == null
      ? 'ChangelogFormatException: $message'
      : 'ChangelogFormatException: Line $line: $message';
}
