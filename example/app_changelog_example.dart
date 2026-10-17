// Shows the installed version's release notes in a "What's new" dialog.
//
// Bundle the changelog as an asset in your app's pubspec.yaml:
//
//   flutter:
//     assets:
//       - CHANGELOG.md
//
// AppChangelog.currentRelease() reads CHANGELOG.md, the installed version and
// the current platform, and returns the notes for that version filtered for
// the platform. Pass `path:` if your changelog lives somewhere else.
//
// AppChangelog.track() remembers the last version the user has seen, so the
// dialog opens once after each update and never on a new install.
import 'package:app_changelog/app_changelog.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppChangelog.track();
  runApp(const MaterialApp(home: HomePage()));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    if (AppChangelog.didUpdate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showWhatsNewOnce());
    }
  }

  Future<void> _showWhatsNewOnce() async {
    await _showWhatsNew();
    await AppChangelog.markVersionSeen();
  }

  Future<void> _showWhatsNew() async {
    final PlatformRelease? release = await AppChangelog.currentRelease();
    if (release == null || release.isEmpty || !mounted) return;

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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('app_changelog')),
        body: Center(
          child: FilledButton(
            onPressed: _showWhatsNew,
            child: const Text("What's new"),
          ),
        ),
      );
}
