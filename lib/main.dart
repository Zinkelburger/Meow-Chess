import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
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
import 'package:uuid/uuid.dart';
import 'application/event_template.dart';
import 'application/failures.dart';
import 'application/tournament_controller.dart';
import 'domain/model.dart';
import 'domain/trf_read.dart';
import 'domain/us_chess.dart';
import 'infrastructure/fide_cli.dart';
import 'infrastructure/native_file_requests.dart';
import 'infrastructure/sqlite_event_repository.dart';
import 'infrastructure/save_location.dart';
import 'ui/brand.dart';
import 'ui/desktop_window.dart';
import 'ui/dialogs.dart';
import 'ui/select.dart';
import 'ui/theme.dart';
import 'ui/workspace.dart';

Future<void> main(List<String> args) async {
  // The FIDE checker and generator run from the command line without the
  // window: `meow_chess -check file.trf` (TEC Manual 3.9.4).
  if (args.isNotEmpty && isFideCliCommand(args.first)) {
    exit(await runFideCli(args));
  }
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
    // The FIDE Dutch engine compiled into the app (third_party/bbpPairings).
    yield LicenseEntryWithLineBreaks([
      'BBP Pairings',
    ], await rootBundle.loadString('assets/licenses/LICENSE-bbpPairings.txt'));
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

  /// An event to open at launch; tests use it in place of a desktop request.
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

  /// Quitting closes the event, so its .meow holds every commit on its own.
  late final AppLifecycleListener exits;

  /// Replaced controllers whose views have not unmounted yet.
  final _retiring = <TournamentController>{};
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
    exits = AppLifecycleListener(
      onExitRequested: () async {
        _closeForExit();
        return AppExitResponse.exit;
      },
    );
  }

  /// A .meow the desktop asked us to open. Dialogs belong to the event on
  /// screen, so they are closed before switching to another one.
  void openFromDesktop(String filename) {
    if (path != null && _samePath(filename, path!)) return;
    navigator.currentState?.popUntil((route) => route.isFirst);
    open(filename);
    if (error != null && controller != null) {
      // Shown over the event still open; the welcome screen must not repeat
      // it after that event is closed.
      final message = error!;
      error = null;
      final context = navigator.currentContext;
      if (context != null) showFailure(context, message);
    }
  }

  @override
  void dispose() {
    newName.dispose();
    files.dispose();
    exits.dispose();
    _closeForExit();
    super.dispose();
  }

  void _closeForExit() {
    _closeRetiring();
    controller?.dispose();
    controller = null;
  }

  void _closeRetiring() {
    final retiring = _retiring.toList();
    _retiring.clear();
    for (final c in retiring) {
      c.dispose();
    }
  }

  /// Disposes [old] once its Workspace has unmounted, so views saving their
  /// state as they dispose still reach an open event file.
  void _retire(TournamentController? old) {
    if (old == null) return;
    _retiring.add(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_retiring.remove(old)) old.dispose();
    });
  }

  void open(String filename) {
    TournamentController? next;
    var opened = false;
    try {
      if (!File(filename).existsSync()) {
        throw const FileSystemException('Event file not found');
      }
      // Reopening an event just closed, before its views unmounted.
      if (_retiring.isNotEmpty && SqliteEventRepository.ownsPath(filename)) {
        _closeRetiring();
      }
      next = TournamentController(SqliteEventRepository(filename));
      if (next.event == null) {
        throw const FormatException('This file has no Meow-Chess event.');
      }
      _retire(controller);
      controller = next;
      path = filename;
      error = null;
      recent = [
        filename,
        ...recent.where((x) => !_samePath(x, filename)),
      ].take(12).toList();
      opened = true;
    } catch (e, stack) {
      Diagnostics.record('open event', 'failed', error: e, stack: stack);
      if (next != controller) next?.dispose();
      error = 'Could not open this event. ${plainMessage(e)}';
    }
    if (opened) {
      try {
        library.writeAsStringSync(jsonEncode(recent), flush: true);
      } catch (e, stack) {
        // The event is open; only the recent list is not remembered.
        Diagnostics.record(
          'remember recent events',
          'failed',
          error: e,
          stack: stack,
        );
      }
    }
    if (mounted) setState(() {});
  }

  /// The new event's name, entered below the welcome screen actions.
  bool naming = false;
  final newName = TextEditingController();

  /// New event like…: the recent event whose set-up the new one copies, or
  /// null for a plain new event. [templating] shows the chooser.
  bool templating = false;
  String? templatePath;

  /// What a template would copy, read from its file; null when unreadable.
  Event? templateSource(String path) {
    try {
      final repository = SqliteEventRepository(path);
      try {
        return repository.load();
      } finally {
        repository.close();
      }
    } catch (e, stack) {
      Diagnostics.record(
        'read event template',
        'failed',
        error: e,
        stack: stack,
        context: {'path': path},
      );
      return null;
    }
  }

  Future<void> create(BuildContext context) async {
    final name = newName.text.trim();
    if (name.isEmpty) {
      setState(() => error = 'Enter the event name.');
      return;
    }
    Event? source;
    if (templating) {
      if (templatePath == null) {
        setState(() => error = 'Choose the event to copy the set-up from.');
        return;
      }
      source = templateSource(templatePath!);
      if (source == null) {
        setState(
          () => error = 'That event could not be read, so nothing was copied.',
        );
        return;
      }
    }
    String? destination;
    try {
      final location = await chooseSaveLocation(
        suggestedName: '${fileStem(name)}.meow',
      );
      if (location == null || !context.mounted) return;
      destination = location.path;
      // Build a fresh event independently: opening the chosen file first would
      // load its previous tournament instead of honoring Replace.
      final fresh = TournamentController(SqliteEventRepository(':memory:'));
      try {
        if (source == null) {
          fresh.create(name);
        } else {
          fresh.change(
            'Create event like ${source.name}',
            templateFrom(
              source,
              name: name,
              date: DateTime.now().toIso8601String().substring(0, 10),
            ),
          );
        }
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
      templating = false;
      templatePath = null;
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
    setState(
      () => recent = recent.where((x) => !_samePath(x, filename)).toList(),
    );
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

  /// Open event: a picker or file-access failure is shown, never dropped as
  /// an unhandled async error.
  Future<void> choose() async {
    try {
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
        _notify(
          'The event can be opened now, but its access could not be remembered. Select it with Open event after restarting.',
        );
      }
    } catch (e, stack) {
      Diagnostics.record('choose event file', 'failed', error: e, stack: stack);
      if (mounted) _notify('Could not choose an event. ${plainMessage(e)}');
    }
  }

  /// Import FIDE report: a TRF (TRF26, TRF16 or TRF06) becomes a new event
  /// file with one FIDE-rated section, saved where the TD chooses. What the
  /// file holds that Meow-Chess cannot keep is listed in the event's notes.
  Future<void> importTrf(BuildContext context) async {
    String? destination;
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'FIDE tournament report',
            extensions: ['trf', 'txt', 'fid'],
          ),
        ],
      );
      if (file == null) return;
      final imported = trfToEvent(
        TrfFile.parse(await readTrfFile(file.path)),
        newId: const Uuid().v4,
        today: DateTime.now().toIso8601String().substring(0, 10),
      );
      var event = imported.event;
      if (imported.warnings.isNotEmpty) {
        event = event.copy(
          notes: [
            'Imported from ${p.basename(file.path)}. Not carried over:',
            for (final w in imported.warnings) '- $w',
          ].join('\n'),
        );
      }
      if (!context.mounted) return;
      final location = await chooseSaveLocation(
        suggestedName: '${fileStem(event.name)}.meow',
      );
      if (location == null || !context.mounted) return;
      destination = location.path;
      final fresh = TournamentController(SqliteEventRepository(':memory:'));
      try {
        fresh.change('Import ${p.basename(file.path)}', event);
        await saveSelectedEvent(fresh.repository, location.path);
      } finally {
        fresh.dispose();
      }
      Diagnostics.record(
        'import TRF',
        'succeeded',
        context: {'path': destination},
      );
      await rememberFileAccess(location.path);
      if (!mounted) return;
      open(location.path);
      if (imported.warnings.isNotEmpty) {
        _notify(
          'Imported. ${imported.warnings.length} ${imported.warnings.length == 1 ? 'thing' : 'things'} could not be carried over; the event notes list them.',
        );
      }
    } catch (e, stack) {
      Diagnostics.record(
        'import TRF',
        'failed',
        error: e,
        stack: stack,
        context: {'path': ?destination},
      );
      if (context.mounted) {
        // A format problem names the line at fault.
        final why = e is TrfFormatException ? '$e.' : plainMessage(e);
        showFailure(context, 'Could not import this file. $why');
      }
    }
  }

  void _notify(String message) {
    final context = navigator.currentContext;
    if (context != null && context.mounted) showFailure(context, message);
  }

  void close() {
    _retire(controller);
    setState(() {
      controller = null;
      path = null;
      error = null;
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
                                  templating = false;
                                  templatePath = null;
                                  error = null;
                                }),
                                icon: const Icon(Icons.add),
                                label: const Text('New tournament'),
                              ),
                              if (recent.isNotEmpty)
                                OutlinedButton.icon(
                                  key: const ValueKey('new-event-like'),
                                  onPressed: () => setState(() {
                                    naming = true;
                                    templating = true;
                                    templatePath ??= recent.first;
                                    error = null;
                                  }),
                                  icon: const Icon(Icons.copy_outlined),
                                  label: const Text('New event like…'),
                                ),
                              OutlinedButton.icon(
                                onPressed: choose,
                                icon: const Icon(Icons.folder_open),
                                label: const Text('Open event'),
                              ),
                              OutlinedButton.icon(
                                key: const ValueKey('import-trf'),
                                onPressed: () => importTrf(context),
                                icon: const Icon(Icons.upload_file_outlined),
                                label: const Text('Import FIDE report'),
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
                                  if (templating)
                                    SizedBox(
                                      width: 320,
                                      child: PlainSelect<String>(
                                        key: const ValueKey(
                                          'new-event-template',
                                        ),
                                        label: 'Set up like',
                                        value: templatePath ?? '',
                                        options: [
                                          for (final filename in recent)
                                            SelectOption(
                                              filename,
                                              p.basenameWithoutExtension(
                                                filename,
                                              ),
                                            ),
                                        ],
                                        onChanged: (v) => setState(() {
                                          templatePath = v;
                                          error = null;
                                        }),
                                      ),
                                    ),
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
                                      templating = false;
                                      newName.clear();
                                    }),
                                    child: const Text('Cancel'),
                                  ),
                                ],
                              ),
                            ),
                          if (naming && templating && templatePath != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Builder(
                                builder: (context) {
                                  final source = templateSource(templatePath!);
                                  return Text(
                                    source == null
                                        ? 'That event could not be read.'
                                        : templateNote(source),
                                    key: const ValueKey(
                                      'new-event-template-note',
                                    ),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  );
                                },
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

/// Whether two names reach the same file: symlinks resolved where the file
/// exists, and case-insensitive on Windows.
bool _samePath(String a, String b) {
  String canonical(String filename) {
    try {
      return File(filename).resolveSymbolicLinksSync();
    } on FileSystemException {
      return p.normalize(p.absolute(filename));
    }
  }

  return p.equals(a, b) || p.equals(canonical(a), canonical(b));
}

/// Turns an event name like "Saturday Quads" into "saturday-quads", and
/// "Torneo Año" into "torneo-ano".
@visibleForTesting
String fileStem(String name) {
  final stem = nameKey(
    name,
  ).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return stem.isEmpty ? 'tournament' : stem;
}
