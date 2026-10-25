import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import 'application/diagnostics.dart';
import 'application/event_template.dart';
import 'application/failures.dart';
import 'application/tournament_controller.dart';
import 'domain/model.dart';
import 'domain/trf_read.dart';
import 'infrastructure/browser_download.dart';
import 'infrastructure/fide_cli.dart' show decodeTrf;
import 'infrastructure/proxy_client.dart';
import 'infrastructure/save_location.dart' show fileStem;
import 'infrastructure/sqlite_event_repository.dart';
import 'infrastructure/sqlite_platform_web.dart';
import 'ui/brand.dart';
import 'ui/dialogs.dart';
import 'ui/select.dart';
import 'ui/theme.dart';
import 'ui/workspace.dart';

/// The browser version (docs/WEB.md): the desktop workspace over events kept
/// in this browser's IndexedDB. `scripts/build_web.sh` builds it.
Future<void> main() async {
  // Requests to other sites go through the hosting site's fetch function;
  // every http.Client() made inside this zone is that proxy.
  await http.runWithClient(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Two tabs over the same IndexedDB would each keep their own copy of an
    // event and overwrite each other's changes, so only one tab may run.
    if (!await _claimThisTab()) {
      runApp(const _OtherTabOpen());
      return;
    }
    await initializeWebStorage();
    LicenseRegistry.addLicense(() async* {
      for (final font in ['Inter', 'SourceCodePro']) {
        yield LicenseEntryWithLineBreaks([
          font,
        ], await rootBundle.loadString('assets/fonts/LICENSE-$font.txt'));
      }
    });
    runApp(const MeowWebApp());
  }, () => ProxyClient(BrowserClient(), Uri.base.resolve('fetch')));
}

/// Holds a Web Lock for as long as this tab is open; false when another tab
/// already holds it.
Future<bool> _claimThisTab() async {
  final claimed = Completer<bool>();
  try {
    web.window.navigator.locks.request(
      'meow-chess',
      web.LockOptions(ifAvailable: true),
      ((web.Lock? lock) {
        claimed.complete(lock != null);
        // Never settles, so the lock is released only when the tab closes.
        return lock == null ? null : Completer<JSAny?>().future.toJS;
      }).toJS,
    );
  } catch (_) {
    // No Web Locks (a very old browser): run without the guard.
    if (!claimed.isCompleted) claimed.complete(true);
  }
  return claimed.future;
}

class _OtherTabOpen extends StatelessWidget {
  const _OtherTabOpen();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Meow-Chess',
    debugShowCheckedModeBanner: false,
    theme: meowTheme(Brightness.light),
    home: const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Text(
            'Meow-Chess is already open in another tab or window. Use that one, or close it and reload this page.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}

/// One event kept in the browser: its database in the IndexedDB file system,
/// and the name and last change shown on the start screen.
class StoredEvent {
  const StoredEvent(this.path, this.name, this.changed);
  final String path, name;
  final DateTime changed;

  Map<String, Object> toJson() => {
    'path': path,
    'name': name,
    'changed': changed.toIso8601String(),
  };

  static StoredEvent fromJson(Map<String, dynamic> json) => StoredEvent(
    json['path'] as String,
    json['name'] as String,
    DateTime.parse(json['changed'] as String),
  );
}

class MeowWebApp extends StatefulWidget {
  const MeowWebApp({super.key});
  @override
  State<MeowWebApp> createState() => _MeowWebAppState();
}

class _MeowWebAppState extends State<MeowWebApp> {
  static const _library = '/library.json', _settings = '/settings.json';

  TournamentController? controller;
  String? path, error;
  bool light = true;
  List<StoredEvent> events = [];
  final navigator = GlobalKey<NavigatorState>();
  final welcomeLogo = GlobalKey();
  bool launchComplete = false;

  /// Replaced controllers whose views have not unmounted yet.
  final _retiring = <TournamentController>{};

  @override
  void initState() {
    super.initState();
    try {
      if (readEventFile(_library) case final bytes?) {
        events = [
          for (final json in jsonDecode(utf8.decode(bytes)) as List)
            StoredEvent.fromJson(json as Map<String, dynamic>),
        ].where((e) => eventFileExists(e.path)).toList();
      }
    } catch (_) {
      error =
          'The list of events in this browser could not be read. Upload a downloaded copy to continue.';
    }
    try {
      if (readEventFile(_settings) case final bytes?) {
        light = jsonDecode(utf8.decode(bytes))['theme'] != 'dark';
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    newName.dispose();
    _closeRetiring();
    controller?.dispose();
    super.dispose();
  }

  void toggleTheme() {
    setState(() => light = !light);
    try {
      writeEventFile(
        _settings,
        utf8.encode(jsonEncode({'theme': light ? 'light' : 'dark'})),
      );
    } catch (_) {
      // The theme still switches; it just will not be remembered.
    }
  }

  void _saveLibrary() {
    events.sort((a, b) => b.changed.compareTo(a.changed));
    try {
      writeEventFile(
        _library,
        utf8.encode(jsonEncode([for (final e in events) e.toJson()])),
      );
    } catch (e, stack) {
      Diagnostics.record(
        'remember browser events',
        'failed',
        error: e,
        stack: stack,
      );
    }
  }

  /// Records [path] as changed now, under the event's current name.
  void _touch(String path, String name) {
    events = [
      StoredEvent(path, name, DateTime.now()),
      ...events.where((e) => e.path != path),
    ];
    _saveLibrary();
  }

  void _closeRetiring() {
    final retiring = _retiring.toList();
    _retiring.clear();
    for (final c in retiring) {
      c.dispose();
    }
  }

  /// Disposes [old] once its Workspace has unmounted, so views saving their
  /// state as they dispose still reach an open event.
  void _retire(TournamentController? old) {
    if (old == null) return;
    _retiring.add(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_retiring.remove(old)) old.dispose();
    });
  }

  /// Opens a stored event; false (with [error] set) when it cannot be read.
  bool open(String filename) {
    TournamentController? next;
    try {
      // Reopening an event just closed, before its views unmounted.
      if (_retiring.isNotEmpty && SqliteEventRepository.ownsPath(filename)) {
        _closeRetiring();
      }
      next = TournamentController(SqliteEventRepository(filename));
      final event = next.event;
      if (event == null) {
        throw const FormatException('This file has no Meow-Chess event.');
      }
      _retire(controller);
      controller = next;
      path = filename;
      error = null;
      _touch(filename, event.name);
      if (mounted) setState(() {});
      return true;
    } catch (e, stack) {
      Diagnostics.record('open event', 'failed', error: e, stack: stack);
      if (next != controller) next?.dispose();
      setState(() => error = 'Could not open this event. ${plainMessage(e)}');
      return false;
    }
  }

  void close() {
    final closing = path, event = controller?.event;
    if (closing != null && event != null) _touch(closing, event.name);
    _retire(controller);
    setState(() {
      controller = null;
      path = null;
      error = null;
    });
  }

  static String _newPath() => '/events/${const Uuid().v4()}.meow';

  static void _deleteDatabase(String path) {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      deleteEventFile('$path$suffix');
    }
  }

  /// Saves [event] as a new stored event and opens it.
  void _store(Event event, String action) {
    final target = _newPath();
    final fresh = TournamentController(SqliteEventRepository(target));
    try {
      fresh.change(action, event);
    } catch (_) {
      fresh.dispose();
      _deleteDatabase(target);
      rethrow;
    }
    fresh.dispose();
    open(target);
  }

  /// The new event's name, entered below the start screen actions.
  bool naming = false;
  final newName = TextEditingController();

  /// New event like…: the stored event whose set-up the new one copies.
  bool templating = false;
  String? templatePath;

  Event? templateSource(String path) {
    if (path == this.path) return controller?.event;
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
      );
      return null;
    }
  }

  void create(BuildContext context) {
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
    final target = _newPath();
    try {
      final fresh = TournamentController(SqliteEventRepository(target));
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
      } finally {
        fresh.dispose();
      }
      newName.clear();
      naming = false;
      templating = false;
      templatePath = null;
      open(target);
    } catch (e, stack) {
      Diagnostics.record('create event', 'failed', error: e, stack: stack);
      _deleteDatabase(target);
      if (context.mounted) showFailure(context, e);
    }
  }

  /// Upload event: a .meow downloaded from here or saved by the desktop app
  /// becomes a new stored event. The file itself is never changed.
  Future<void> upload() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Meow-Chess event', extensions: ['meow']),
        ],
      );
      if (file == null || !mounted) return;
      final target = _newPath();
      writeEventFile(target, _withoutWal(await file.readAsBytes()));
      if (!mounted) return;
      if (!open(target)) _deleteDatabase(target);
    } catch (e, stack) {
      Diagnostics.record('upload event', 'failed', error: e, stack: stack);
      if (mounted) _notify('Could not upload this event. ${plainMessage(e)}');
    }
  }

  /// The desktop app keeps events in WAL mode, which needs shared memory the
  /// browser's SQLite lacks. A closed desktop event has no pending WAL, so its
  /// header can say rollback journal instead, as `PRAGMA journal_mode=DELETE`
  /// would write it (file format bytes 18 and 19).
  static Uint8List _withoutWal(Uint8List bytes) {
    const magic = 'SQLite format 3\u0000';
    if (bytes.length < 100 ||
        String.fromCharCodes(bytes.sublist(0, 16)) != magic ||
        bytes[18] != 2) {
      return bytes;
    }
    return Uint8List.fromList(bytes)
      ..[18] = 1
      ..[19] = 1;
  }

  /// Import FIDE report: a TRF becomes a new event with one FIDE-rated
  /// section; what Meow-Chess cannot keep is listed in the event's notes.
  Future<void> importTrf(BuildContext context) async {
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
        TrfFile.parse(decodeTrf(await file.readAsBytes())),
        newId: const Uuid().v4,
        today: DateTime.now().toIso8601String().substring(0, 10),
      );
      var event = imported.event;
      if (imported.warnings.isNotEmpty) {
        event = event.copy(
          notes: [
            'Imported from ${file.name}. Not carried over:',
            for (final w in imported.warnings) '- $w',
          ].join('\n'),
        );
      }
      if (!mounted) return;
      _store(event, 'Import ${file.name}');
      if (imported.warnings.isNotEmpty) {
        _notify(
          'Imported. ${imported.warnings.length} ${imported.warnings.length == 1 ? 'thing' : 'things'} could not be carried over; the event notes list them.',
        );
      }
    } catch (e, stack) {
      Diagnostics.record('import TRF', 'failed', error: e, stack: stack);
      if (context.mounted) {
        final why = e is TrfFormatException ? '$e.' : plainMessage(e);
        showFailure(context, 'Could not import this file. $why');
      }
    }
  }

  /// Download: a verified copy of a stored event, which the desktop app or
  /// another browser can open.
  void download(BuildContext context, StoredEvent stored) {
    try {
      final List<int> bytes;
      if (stored.path == path && controller != null) {
        bytes = controller!.repository.snapshotBytes();
      } else {
        final repository = SqliteEventRepository(stored.path);
        try {
          bytes = repository.snapshotBytes();
        } finally {
          repository.close();
        }
      }
      downloadFile('${fileStem(stored.name)}.meow', bytes);
    } catch (e, stack) {
      Diagnostics.record('download event', 'failed', error: e, stack: stack);
      showFailure(context, 'Could not download this event. ${plainMessage(e)}');
    }
  }

  Future<void> delete(BuildContext context, StoredEvent stored) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${stored.name}?'),
        content: const Text(
          'This removes the event from this browser. Download a copy first if you may need it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      _closeRetiring();
      _deleteDatabase(stored.path);
      setState(() => events.removeWhere((e) => e.path == stored.path));
      _saveLibrary();
    } catch (e, stack) {
      Diagnostics.record('delete event', 'failed', error: e, stack: stack);
      if (context.mounted) showFailure(context, e);
    }
  }

  void _notify(String message) {
    final context = navigator.currentContext;
    if (context != null && context.mounted) showFailure(context, message);
  }

  static String _changed(DateTime t) {
    final now = DateTime.now();
    final clock =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return 'Changed today $clock';
    }
    return 'Changed ${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    title: 'Meow-Chess',
    debugShowCheckedModeBanner: false,
    theme: meowTheme(Brightness.light),
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
            path: 'Saved in this browser',
            onClose: close,
            onTheme: toggleTheme,
          )
        : Builder(builder: _startScreen),
  );

  Widget _startScreen(BuildContext context) {
    final muted = TextStyle(
      fontSize: 13,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Scaffold(
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
                      if (events.isNotEmpty)
                        OutlinedButton.icon(
                          key: const ValueKey('new-event-like'),
                          onPressed: () => setState(() {
                            naming = true;
                            templating = true;
                            templatePath ??= events.first.path;
                            error = null;
                          }),
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('New event like…'),
                        ),
                      OutlinedButton.icon(
                        onPressed: upload,
                        icon: const Icon(Icons.upload_outlined),
                        label: const Text('Upload event'),
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
                                key: const ValueKey('new-event-template'),
                                label: 'Set up like',
                                value: templatePath ?? '',
                                options: [
                                  for (final stored in events)
                                    SelectOption(stored.path, stored.name),
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
                            child: const Text('Create'),
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
                            key: const ValueKey('new-event-template-note'),
                            style: muted,
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
                  Text(
                    'Events in this browser',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Events are saved in this browser as you work, and nowhere else. Download a copy after each round to keep it safe; a copy also opens in the Meow-Chess desktop app.',
                    style: muted,
                  ),
                  const SizedBox(height: 12),
                  if (events.isEmpty) Text('None yet.', style: muted),
                  for (final stored in events)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(stored.name),
                        subtitle: Text(_changed(stored.changed)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Download a copy',
                              icon: const Icon(
                                Icons.download_outlined,
                                size: 18,
                              ),
                              onPressed: () => download(context, stored),
                            ),
                            IconButton(
                              tooltip: 'Delete from this browser',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => delete(context, stored),
                            ),
                          ],
                        ),
                        onTap: () => open(stored.path),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
