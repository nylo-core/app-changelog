import 'dart:io';

import 'package:app_changelog/src/cli.dart';

/// Reads build names from CHANGELOG.md and checks it before a release.
///
/// Run `dart run app_changelog --help` for usage.
Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments, out: stdout, err: stderr);
}
