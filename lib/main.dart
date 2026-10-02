import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'application/failures.dart';
import 'application/tournament_controller.dart';
import 'application/demo.dart';
import 'infrastructure/native_file_requests.dart';
import 'infrastructure/sqlite_event_repository.dart';
import 'ui/brand.dart';
import 'ui/desktop_window.dart';
import 'ui/dialogs.dart';
import 'ui/theme.dart';
import 'ui/workspace.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDesktopWindow();
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
    // A .meow named on the command line arrives through NativeFileRequests,
    // along with any double-clicked while the app is running.
    MeowApp(dataDirectory: directory),
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
  bool light = true;
  List<String> recent = [];
  final navigator = GlobalKey<NavigatorState>();
  late final files = NativeFileRequests(open: openFromDesktop);
  File get library => File(p.join(widget.dataDirectory.path, 'library.json'));

  /// App-wide choices that outlive one event, such as the theme.
  File get settings => File(p.join(widget.dataDirectory.path, 'settings.json'));

  void toggleTheme() {
    setState(() => light = !light);
    try {
      settings.writeAsStringSync(
        jsonEncode({'theme': light ? 'light' : 'dark'}),
        flush: true,
      );
    } catch (_) {
      // The theme still switches; it just will not be remembered.
    }
  }

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
    try {
      if (settings.existsSync()) {
        light = jsonDecode(settings.readAsStringSync())['theme'] != 'dark';
      }
    } catch (_) {}
    if (widget.initialPath != null) open(widget.initialPath!);
    files.start();
  }

  /// A .meow the desktop asked us to open. Dialogs belong to the event on
  /// screen, so they are closed before switching to another one.
  void openFromDesktop(String filename) {
    if (filename == path) return;
    navigator.currentState?.popUntil((route) => route.isFirst);
    open(filename);
  }

  @override
  void dispose() {
    newName.dispose();
    files.dispose();
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
      error = 'Could not open this event. ${plainMessage(e)}';
    }
    if (mounted) setState(() {});
  }

  /// The new event's name, typed in place on the welcome screen.
  bool naming = false;
  final newName = TextEditingController();

  Future<void> create(BuildContext context) async {
    final name = newName.text.trim();
    if (name.isEmpty) {
      setState(() => error = 'Enter the event name.');
      return;
    }
    final location = await getSaveLocation(
      suggestedName: '${_fileStem(name)}.meow',
    );
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
      newName.clear();
      naming = false;
      open(location.path, name: name);
    }
  }

  /// When an event file last changed, for the recent list.
  String changed(String filename) {
    try {
      final file = File(filename);
      if (!file.existsSync()) return 'File not found';
      final t = file.lastModifiedSync(), now = DateTime.now();
      final clock =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      if (t.year == now.year && t.month == now.month && t.day == now.day) {
        return 'Changed today $clock';
      }
      return 'Changed ${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Unreadable';
    }
  }

  /// Takes an event off the recent list; the file itself is untouched.
  void forget(String filename) {
    setState(() => recent = recent.where((x) => x != filename).toList());
    try {
      library.writeAsStringSync(jsonEncode(recent), flush: true);
    } catch (_) {}
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
    navigatorKey: navigator,
    title: 'Meow-Chess',
    debugShowCheckedModeBanner: false,
    theme: meowTheme(Brightness.light),
    // Switch light/dark instantly rather than cross-fading every colour.
    themeAnimationStyle: AnimationStyle.noAnimation,
    darkTheme: meowTheme(Brightness.dark),
    themeMode: light ? ThemeMode.light : ThemeMode.dark,
    home: controller != null
        ? Workspace(
            key: ValueKey(path),
            controller: controller!,
            path: path!,
            onClose: close,
            onTheme: toggleTheme,
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
                            const MeowLogo(size: 88),
                            const SizedBox(width: 24),
                            Text(
                              'Meow Chess',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: toggleTheme,
                              icon: Icon(
                                light
                                    ? Icons.dark_mode_outlined
                                    : Icons.light_mode_outlined,
                              ),
                              label: Text(light ? 'Dark mode' : 'Light mode'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'Run Swiss and quad chess tournaments. Each event is saved as a .meow file on this computer and works without internet.',
                        ),
                        const SizedBox(height: 24),
                        if (naming)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 320,
                                  child: TextField(
                                    key: const ValueKey('new-event-name'),
                                    controller: newName,
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Event name',
                                      hintText: 'Saturday Quads',
                                    ),
                                    onSubmitted: (_) => create(context),
                                  ),
                                ),
                                FilledButton(
                                  onPressed: () => create(context),
                                  child: const Text('Choose where to save…'),
                                ),
                                TextButton(
                                  onPressed: () => setState(() {
                                    naming = false;
                                    newName.clear();
                                  }),
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                          ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            if (!naming)
                              FilledButton.icon(
                                onPressed: () => setState(() {
                                  naming = true;
                                  error = null;
                                }),
                                icon: const Icon(Icons.add),
                                label: const Text('New tournament'),
                              ),
                            OutlinedButton.icon(
                              onPressed: choose,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Open event file'),
                            ),
                            TextButton.icon(
                              onPressed: practice,
                              icon: const Icon(Icons.science_outlined),
                              label: const Text('Try a practice event'),
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
                                  '${changed(filename)} · $filename',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  tooltip: 'Remove from recent events',
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () => forget(filename),
                                ),
                                onTap: () => open(filename),
                              ),
                            ),
                        ],
                        const SizedBox(height: 32),
                        const Text(
                          'Test version: Swiss pairings and US Chess rating reports are not yet certified.',
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

/// Turns an event name like "Saturday Quads" into "saturday-quads".
String _fileStem(String name) {
  final stem = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return stem.isEmpty ? 'tournament' : stem;
}
