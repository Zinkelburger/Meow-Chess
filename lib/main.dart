import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'application/tournament_controller.dart';
import 'application/demo.dart';
import 'infrastructure/sqlite_event_repository.dart';
import 'ui/dialogs.dart';
import 'ui/theme.dart';
import 'ui/workspace.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final configured = Platform.environment['MEOW_DATA_DIR'];
  final directory = configured == null
      ? await getApplicationSupportDirectory()
      : Directory(configured);
  await directory.create(recursive: true);
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Inter', 'SourceCodePro']) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString('assets/fonts/LICENSE-$font.txt'));
    }
  });
  runApp(
    MeowApp(
      dataDirectory: directory,
      initialPath: args.isNotEmpty ? args.first : null,
    ),
  );
}

class MeowApp extends StatefulWidget {
  const MeowApp({required this.dataDirectory, this.initialPath, super.key});
  final Directory dataDirectory;
  final String? initialPath;
  @override
  State<MeowApp> createState() => _MeowAppState();
}

class _MeowAppState extends State<MeowApp> {
  TournamentController? controller;
  String? path, error;
  bool light = false;
  List<String> recent = [];
  File get library => File(p.join(widget.dataDirectory.path, 'library.json'));
  @override
  void initState() {
    super.initState();
    try {
      if (library.existsSync()) {
        recent = List<String>.from(jsonDecode(library.readAsStringSync()));
      }
    } catch (_) {
      error =
          'Recent-event list could not be read. Your event files are unaffected.';
    }
    if (widget.initialPath != null) open(widget.initialPath!);
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void open(String filename, {String? name, bool demo = false}) {
    TournamentController? next;
    try {
      if (name == null && !demo && !File(filename).existsSync()) {
        throw const FileSystemException('Event file not found');
      }
      next = TournamentController(SqliteEventRepository(filename));
      if (demo) {
        populatePractice(next);
      } else if (next.event == null) {
        if (name == null) {
          throw const FormatException('This file has no Meow-Chess event.');
        }
        next.create(name);
      }
      controller?.dispose();
      controller = next;
      path = filename;
      error = null;
      recent = [
        filename,
        ...recent.where((x) => x != filename),
      ].take(12).toList();
      library.writeAsStringSync(jsonEncode(recent), flush: true);
    } catch (e) {
      if (next != controller) next?.dispose();
      error = 'Could not open this event: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> create(BuildContext context) async {
    final fields = await editFields(
      context,
      title: 'A new tournament',
      saveLabel: 'Choose event file',
      fields: const [FieldSpec('name', 'Event name', required: true)],
      values: const {'name': 'Saturday Quads'},
    );
    if (fields == null) return;
    final location = await getSaveLocation(suggestedName: 'tournament.meow');
    if (location != null) {
      if (File(location.path).existsSync()) {
        if (context.mounted) {
          showFailure(
            context,
            'Choose a new filename. Existing event files are never overwritten.',
          );
        }
        return;
      }
      open(location.path, name: fields['name']);
    }
  }

  Future<void> choose() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Meow-Chess event', extensions: ['meow']),
      ],
    );
    if (file != null) open(file.path);
  }

  void practice() => open(
    p.join(
      widget.dataDirectory.path,
      'practice-${DateTime.now().microsecondsSinceEpoch}.meow',
    ),
    demo: true,
  );
  void close() {
    controller?.dispose();
    setState(() {
      controller = null;
      path = null;
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Meow-Chess',
    debugShowCheckedModeBanner: false,
    theme: meowTheme(Brightness.light),
    darkTheme: meowTheme(Brightness.dark),
    themeMode: light ? ThemeMode.light : ThemeMode.dark,
    home: controller != null
        ? Workspace(
            key: ValueKey(path),
            controller: controller!,
            path: path!,
            onClose: close,
            onTheme: () => setState(() => light = !light),
          )
        : Builder(
            builder: (context) => Scaffold(
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: ListView(
                      padding: const EdgeInsets.all(40),
                      shrinkWrap: true,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.pets,
                              size: 32,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'meow chess',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -1,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Toggle light / dark',
                              onPressed: () => setState(() => light = !light),
                              icon: const Icon(Icons.contrast),
                            ),
                          ],
                        ),
                        const SizedBox(height: 64),
                        Text(
                          'A calmer tournament day.',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Check in the room. Post the round. Keep every result.\nYour event lives in a file you own, and works offline.',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 32),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              onPressed: () => create(context),
                              icon: const Icon(Icons.add),
                              label: const Text('New tournament'),
                            ),
                            OutlinedButton.icon(
                              onPressed: choose,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Open event'),
                            ),
                            TextButton.icon(
                              onPressed: practice,
                              icon: const Icon(Icons.science_outlined),
                              label: const Text('Explore a practice event'),
                            ),
                          ],
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 48),
                        if (recent.isNotEmpty) ...[
                          Text(
                            'Recent events',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          for (final filename in recent)
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.description_outlined),
                                title: Text(
                                  p.basenameWithoutExtension(filename),
                                ),
                                subtitle: Text(
                                  filename,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => open(filename),
                              ),
                            ),
                        ],
                        const SizedBox(height: 32),
                        const Text(
                          'Development pilot · Swiss pairing and US Chess portal acceptance are not yet qualified.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
  );
}
