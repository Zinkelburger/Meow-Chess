import 'dart:async';
import 'dart:isolate';
import 'dart:math' show Random;

import 'headless_foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/bye_policy.dart';
import '../domain/fide.dart';
import '../domain/fide_pairing.dart' show fideDutchPolicy;
import '../domain/history.dart';
import '../domain/holland.dart';
import '../domain/knockout.dart';
import '../domain/result_correction.dart';
import '../domain/rulings.dart';
import '../domain/model.dart';
import '../domain/member_observation.dart';
import '../domain/rating_update.dart';
import '../domain/ladder.dart';
import '../domain/pairing.dart';
import '../domain/trf.dart' show bakuGroupLast;
import '../domain/us_chess.dart';
import 'event_repository.dart';
import 'diagnostics.dart';
import 'failures.dart';
import 'workspace_state_core.dart';

part 'controller_bughouse.dart';
part 'controller_history.dart';
part 'controller_knockout.dart';
part 'controller_ladder.dart';
part 'controller_quads.dart';
part 'controller_ratings.dart';
part 'controller_results.dart';
part 'controller_roster.dart';
part 'controller_rounds.dart';
part 'controller_sections.dart';

class PairingBatch {
  const PairingBatch(this.revision, this.rounds, this.issues);
  final int revision;
  final Map<String, Round> rounds;
  final Map<String, String> issues;
}

/// What every command group needs from the controller: the current event,
/// the one way to commit a change, and lookups that refuse plainly.
mixin _CommandContext {
  EventRepository get repository;
  Event? get event;

  /// Commits [next] as one audited revision.
  void change(String action, Event next);
  String newId();

  /// Copies the saved event to the backup folder, warning on failure.
  void secondaryBackup();

  Section _section(String id) =>
      event!.sections.where((s) => s.id == id).firstOrNull ??
      (throw const TournamentException('That section no longer exists.'));
}

/// The tournament commands shared by the desktop app and the headless tools.
/// Each command validates against the current event and commits at most one
/// audited revision through [change]; the command groups live in part files.
class TournamentControllerCore extends ChangeNotifier
    with
        _CommandContext,
        _ControllerHistory,
        _RosterCommands,
        _RatingCommands,
        _SectionCommands,
        _BughouseCommands,
        _KnockoutCommands,
        _QuadCommands,
        _RoundCommands,
        _ResultCommands {
  TournamentControllerCore(this.repository) {
    try {
      event = repository.load();
    } catch (_) {
      // Construction did not return an owner who could release the connection.
      // A close failure must not hide the original invalid-event error.
      try {
        repository.close();
      } catch (_) {}
      rethrow;
    }
  }
  @override
  final EventRepository repository;
  late final _workspaceState = WorkspaceStateCore(repository);
  WorkspaceStateCore get workspaceState => _workspaceState;
  @override
  Event? event;
  String? backupWarning;
  @override
  bool _closed = false;
  @override
  String newId() => const Uuid().v4();
  void create(String name, {bool practice = false}) => change(
    'Create event',
    Event(
      id: newId(),
      name: name,
      date: DateTime.now().toIso8601String().substring(0, 10),
      practice: practice,
    ),
  );

  /// Commits [next] as one audited revision. A command that changes nothing
  /// (a retried click, an unchanged dialog) is acknowledged without a revision.
  @override
  void change(String action, Event next) {
    final context = <String, Object?>{
      'action': action,
      'eventId': next.id,
      'revision': event?.revision,
      'players': next.players.length,
    };
    Diagnostics.record('save event', 'started', context: context);
    try {
      if (_closed) throw const TournamentException('This event has closed.');
      if (event != null && next.encode() == event!.encode()) {
        Diagnostics.record('save event', 'unchanged', context: context);
        return;
      }
      _refuseNewDuplicateSectionName(event, next);
      event = repository.commit(
        next,
        expectedRevision: event?.revision ?? 0,
        action: action,
      );
      _graph = null;
      Diagnostics.record(
        'save event',
        'succeeded',
        context: {...context, 'revision': event!.revision},
      );
    } catch (error, stack) {
      Diagnostics.record(
        'save event',
        'failed',
        context: context,
        error: error,
        stack: stack,
      );
      rethrow;
    }
    // Outside the try: the save has succeeded, so a failing listener must not
    // be logged as a failed save.
    notifyListeners();
  }

  /// Refuses a change that gives two sections the same name. Older files
  /// that already hold duplicates still open and save.
  static void _refuseNewDuplicateSectionName(Event? previous, Event next) {
    Map<String, int> count(Iterable<Section> sections) {
      final out = <String, int>{};
      for (final s in sections) {
        final key = s.name.trim().toLowerCase();
        out[key] = (out[key] ?? 0) + 1;
      }
      return out;
    }

    final before = count(previous?.sections ?? const []);
    for (final MapEntry(:key, :value) in count(next.sections).entries) {
      if (value > 1 && value > (before[key] ?? 0)) {
        // Name the section that already had it, as the TD knows it.
        final name = [
          ...?previous?.sections,
          ...next.sections,
        ].firstWhere((s) => s.name.trim().toLowerCase() == key).name.trim();
        throw TournamentException(
          'There is already a section called $name. Choose another name.',
        );
      }
    }
  }

  @override
  void secondaryBackup() {
    final e = event!;
    if (e.backupFolder.isEmpty) return;
    try {
      final destination = p.join(
        e.backupFolder,
        '${e.id}-r${e.revision}-${DateTime.now().microsecondsSinceEpoch}.meow',
      );
      repository.backup(destination);
      repository.writePreference(
        'lastBackup',
        '${e.revision}|$destination|${DateTime.now().toUtc().toIso8601String()}',
      );
      backupWarning = null;
    } catch (error, stack) {
      // The event file is saved; a failed copy is a warning, not a failure.
      Diagnostics.record(
        'secondary backup',
        'failed',
        context: {'eventId': e.id, 'revision': e.revision},
        error: error,
        stack: stack,
      );
      backupWarning =
          'Saved to the event file, but the backup copy failed. ${plainMessage(error)}';
    }
    notifyListeners();
  }

  /// Closes the event file. Safe to call more than once, so an owner may
  /// release early and still dispose.
  void releaseResources() {
    if (_closed) return;
    _closed = true;
    workspaceState.dispose();
    repository.close();
  }

  @override
  void dispose() {
    releaseResources();
    super.dispose();
  }
}
