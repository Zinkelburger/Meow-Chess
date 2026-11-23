import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../application/diagnostics.dart';
import '../application/event_repository.dart';
import '../domain/model.dart';
import 'artifact_file.dart';
import 'artifact_save.dart';
import 'sqlite_event_repository.dart';
import 'swisssys_export.dart';

/// The folder a new event called [name] gets: the name as typed, less the
/// characters file systems refuse, so "Tornado #150" stays "Tornado #150".
String eventFolderName(String name) {
  var folder = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (folder.length > 80) folder = folder.substring(0, 80).trimRight();
  if (folder.isEmpty) return 'Tournament';
  // Names Windows keeps for devices, with or without an extension.
  final device = RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$',
    caseSensitive: false,
  );
  return device.hasMatch(folder) ? '$folder tournament' : folder;
}

/// Makes the folder for a new event called [name] inside [parent] and
/// returns it, with whether it was made just now. An empty folder of that
/// name is used as it is (and is not [created], so a failed save leaves
/// it); one with files in it belongs to something else and is refused.
({String path, bool created}) createEventFolder(String parent, String name) {
  if (!Directory(parent).existsSync()) {
    throw TournamentException(
      '$parent can no longer be found. Choose where tournament folders go.',
    );
  }
  final folder = Directory(p.join(parent, eventFolderName(name)));
  final type = FileSystemEntity.typeSync(folder.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    folder.createSync();
    return (path: folder.path, created: true);
  }
  if (type == FileSystemEntityType.directory && folder.listSync().isEmpty) {
    return (path: folder.path, created: false);
  }
  throw TournamentException(
    '${p.basename(folder.path)} already exists in $parent. Give this event '
    'another name, or open the event in that folder.',
  );
}

const _ownFolderKey = 'event-folder';

String _normal(String folder) => p.normalize(p.absolute(folder));

/// Records in a new event's file that [folder] was made for it, so files
/// are saved there without asking. Called before the file is first saved.
void markEventFolder(EventRepository repository, String folder) =>
    repository.writePreference(_ownFolderKey, _normal(folder));

/// The folder an event file has to itself, where exports are saved without
/// asking: the one this app made for the event ([markEventFolder]). Null
/// for any other folder (an older event kept alone on the Desktop, or a
/// copy saved elsewhere), when another event file shares it, when the
/// event is not in a file, or when the folder cannot be read (as on a Mac
/// where only the file itself was chosen).
String? eventFolder(EventRepository? repository) {
  if (kIsWeb || repository is! SqliteEventRepository) return null;
  if (repository.path == ':memory:') return null;
  final folder = p.dirname(p.absolute(repository.path));
  try {
    if (repository.readPreference(_ownFolderKey) != _normal(folder)) {
      return null;
    }
    final events = Directory(folder)
        .listSync(followLinks: false)
        .where((f) => f is File && p.extension(f.path).toLowerCase() == '.meow')
        .length;
    return events == 1 ? folder : null;
  } on FileSystemException {
    return null;
  }
}

/// Saves a report into the event's own folder, or through the save dialog
/// when the event has none. Null when the dialog was cancelled.
Future<String?> saveForEvent(
  EventRepository? repository,
  String name,
  List<int> bytes, {
  Future<String?> Function(String, List<int>) ask = saveArtifact,
}) async {
  final folder = eventFolder(repository);
  if (folder == null) return ask(name, bytes);
  final path = p.join(folder, name);
  writeArtifact(path, bytes);
  return path;
}

/// Keeps each section's SwissSys file current in the event's own folder, as
/// SwissSys does in its own: `Open.S0C` before round 1, `Open.S1A` once
/// round 1 is paired, `Open.S1C` when its results are in, then `Open.S2A`.
/// Files of earlier rounds stay; one for a round taken back is removed.
///
/// Only files this event wrote are ever replaced or removed. The names it
/// wrote, and the folder they are in, are kept with the event, so a
/// SwissSys file from another event in the same folder (an event file kept
/// alone in Documents, say) is left exactly as it is.
class SwissSysFolderFiles {
  SwissSysFolderFiles(this.repository);
  final EventRepository repository;
  int? _revision;
  final _written = <String, Uint8List>{};

  static const _key = 'swisssys-files';

  /// The SwissSys files this event wrote in [folder], by name.
  static Set<String> owned(EventRepository repository, String folder) {
    try {
      final saved = jsonDecode(repository.readPreference(_key) ?? '{}');
      if (saved is! Map || saved['folder'] != folder) return {};
      return {for (final n in saved['files'] as List? ?? const []) '$n'};
    } catch (_) {
      return {};
    }
  }

  static void _own(EventRepository repository, String folder, Set<String> n) =>
      repository.writePreference(
        _key,
        jsonEncode({'folder': folder, 'files': n.toList()..sort()}),
      );

  /// Records files the director saved into the event's own folder with
  /// Save SwissSys files, so later rounds keep them current too.
  static void remember(
    EventRepository repository,
    String folder,
    Iterable<String> names,
  ) {
    final mine = owned(repository, folder);
    if (mine.containsAll(names)) return;
    _own(repository, folder, {...mine, ...names});
  }

  /// Brings the folder up to date with [e]. Only files whose content
  /// changed are written. A failure is logged, never thrown: the event
  /// itself is saved either way.
  void update(Event e) {
    if (e.revision == _revision) return;
    _revision = e.revision;
    final folder = eventFolder(repository);
    if (folder == null) return;
    try {
      final mine = owned(repository, folder);
      final before = {...mine};
      final files = swissSysFiles(e);
      for (final MapEntry(key: name, value: bytes) in files.entries) {
        final path = p.join(folder, name);
        final exists = File(path).existsSync();
        // Another event's file of the same name is never written over.
        if (exists && !mine.contains(name)) continue;
        final previous = _written[name];
        if (previous != null && _same(previous, bytes) && exists) continue;
        writeArtifact(path, bytes);
        _written[name] = bytes;
        mine.add(name);
      }
      _removeTakenBack(folder, files.keys, mine);
      if (mine.length != before.length || !mine.containsAll(before)) {
        _own(repository, folder, mine);
      }
    } catch (error, stack) {
      Diagnostics.record(
        'SwissSys files',
        'failed',
        error: error,
        stack: stack,
        context: {'folder': folder, 'revision': e.revision},
      );
    }
  }

  /// Removes this event's files for rounds after the current one, and the
  /// completed file of a round reopened, so a screen never shows pairings
  /// or results that were taken back. [mine] loses the names removed.
  void _removeTakenBack(
    String folder,
    Iterable<String> current,
    Set<String> mine,
  ) {
    final pattern = RegExp(r'^(.*)\.S(\d+)([AC])$', caseSensitive: false);
    final latest = <String, (int, String)>{
      for (final name in current)
        if (pattern.firstMatch(name) case final m?)
          m[1]!.toLowerCase(): (int.parse(m[2]!), m[3]!.toUpperCase()),
    };
    for (final name in mine.toList()) {
      final m = pattern.firstMatch(name);
      if (m == null) continue;
      final (round, letter) = latest[m[1]!.toLowerCase()] ?? (-1, '');
      if (round < 0) continue;
      final n = int.parse(m[2]!);
      final reopened =
          n == round && letter == 'A' && m[3]!.toUpperCase() == 'C';
      if (n > round || reopened) {
        final file = File(p.join(folder, name));
        if (file.existsSync()) file.deleteSync();
        _written.remove(name);
        mine.remove(name);
      }
    }
  }
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
