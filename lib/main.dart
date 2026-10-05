import 'dart:convert';
import 'dart:io';
import 'application/diagnostics.dart';
import 'infrastructure/diagnostic_log.dart';
import 'infrastructure/event_save.dart';
import 'infrastructure/file_access.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'application/failures.dart';
import 'application/tournament_controller.dart';
import 'infrastructure/native_file_requests.dart';
import 'infrastructure/sqlite_event_repository.dart';
import 'infrastructure/save_location.dart';
import 'ui/brand.dart';
import 'ui/desktop_window.dart';
import 'ui/dialogs.dart';
import 'ui/theme.dart';
import 'ui/workspace.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configured = Platform.environment['MEOW_DATA_DIR'];
  final directory = configured == null
      ? await getApplicationSupportDirectory()
      : Directory(configured);
  await directory.create(recursive: true);
  DiagnosticLog.initialize(directory);
  await restoreFileAccess();
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    Diagnostics.record(
      'flutter',
      'failed',
      error: details.exception,
      stack: details.stack,
      context: {
        'library': details.library,
        'context': details.context?.toDescription(),
      },
    );
    previousFlutterError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    Diagnostics.record(
      'unhandled async operation',
      'failed',
      error: error,
      stack: stack,
    );
    return true;
  };
  await initializeDesktopWindow();
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
  final welcomeLogo = GlobalKey();
  bool launchComplete = false;
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
    if (error != null && controller != null) {
      final context = navigator.currentContext;
      if (context != null) showFailure(context, error!);
    }
  }

  @override
  void dispose() {
    newName.dispose();
    files.dispose();
    controller?.dispose();
    super.dispose();
  }

  void open(String filename) {
    TournamentController? next;
    try {
      if (!File(filename).existsSync()) {
        throw const FileSystemException('Event file not found');
      }
      next = TournamentController(SqliteEventRepository(filename));
      if (next.event == null) {
        throw const FormatException('This file has no Meow-Chess event.');
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
    } catch (e, stack) {
      Diagnostics.record('open event', 'failed', error: e, stack: stack);
      if (next != controller) next?.dispose();
      error = 'Could not open this event. ${plainMessage(e)}';
    }
    if (mounted) setState(() {});
  }

  /// The new event's name, entered below the welcome screen actions.
  bool naming = false;
  final newName = TextEditingController();

  Future<void> create(BuildContext context) async {
    final name = newName.text.trim();
    if (name.isEmpty) {
      setState(() => error = 'Enter the event name.');
      return;
    }
    String? destination;
    try {
      final location = await chooseSaveLocation(
        suggestedName: '${_fileStem(name)}.meow',
      );
      if (location == null || !context.mounted) return;
      destination = location.path;
      // Build a fresh event independently: opening the chosen file first would
      // load its previous tournament instead of honoring Replace.
      final fresh = TournamentController(SqliteEventRepository(':memory:'));
      try {
        fresh.create(name);
        await saveSelectedEvent(fresh.repository, location.path);
        Diagnostics.record(
          'create event file',
          'succeeded',
          context: {'path': destination},
        );
      } finally {
        fresh.dispose();
      }
      final remembered = await rememberFileAccess(location.path);
      if (!mounted) return;
      newName.clear();
      naming = false;
      open(location.path);
      if (!remembered && context.mounted) {
        showFailure(
          context,
          'The event was saved, but its access could not be remembered. Select it with Open event after restarting.',
        );
      }
    } catch (e, stack) {
      Diagnostics.record(
        'create event file',
        'failed',
        error: e,
        stack: stack,
        context: {'path': ?destination},
      );
      if (context.mounted) showFailure(context, e);
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

  Future<void> reveal(BuildContext context, String filename) async {
    try {
      await files.reveal(File(filename).absolute.path);
    } catch (e, stack) {
      Diagnostics.record('reveal event file', 'failed', error: e, stack: stack);
      if (context.mounted) {
        showFailure(
          context,
          'Could not show this file in the file explorer. ${plainMessage(e)}',
        );
      }
    }
  }

  Future<void> choose() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Meow-Chess event', extensions: ['meow']),
      ],
    );
    if (file == null) return;
    final remembered = await rememberFileAccess(file.path);
    if (!mounted) return;
    open(file.path);
    if (!remembered) {
      final context = navigator.currentContext;
      if (context != null && context.mounted) {
        showFailure(
          context,
          'The event can be opened now, but its access could not be remembered. Select it with Open event after restarting.',
        );
      }
    }
  }

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
    builder: (context, child) => LogoEntrance(
      targetKey: welcomeLogo,
      onComplete: () => setState(() => launchComplete = true),
      child: child!,
    ),
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
              body: SelectionArea(
                child: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: ListView(
                        padding: const EdgeInsets.all(40),
                        children: [
                          WelcomeBrandHeader(
                            logoKey: welcomeLogo,
                            showLogo: launchComplete,
                            light: light,
                            onTheme: toggleTheme,
                          ),
                          const SizedBox(height: 32),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
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
                                label: const Text('Open event'),
                              ),
                            ],
                          ),
                          if (naming)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
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
                                      ),
                                      onSubmitted: (_) => create(context),
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: () => create(context),
                                    child: const Text('Save'),
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
                                  leading: const Icon(
                                    Icons.description_outlined,
                                  ),
                                  title: Text(
                                    p.basenameWithoutExtension(filename),
                                  ),
                                  subtitle: Text(
                                    '${changed(filename)} · $filename',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'View in file explorer',
                                        icon: const Icon(
                                          Icons.folder_open_outlined,
                                          size: 18,
                                        ),
                                        onPressed: () =>
                                            reveal(context, filename),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove from recent events',
                                        icon: const Icon(Icons.close, size: 18),
                                        onPressed: () => forget(filename),
                                      ),
                                    ],
                                  ),
                                  onTap: () => open(filename),
                                ),
                              ),
                          ],
                        ],
                      ),
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
