import '../domain/history.dart';
import '../domain/model.dart';

/// What has become of an open event's file.
enum EventFileProblem {
  /// Moved, renamed, trashed, deleted or replaced while open. The open event
  /// still takes changes, but they are no longer in a file at that name.
  moved,

  /// The drive or folder holding it cannot be reached, so nothing saves.
  unreachable,
}

/// A change that could not be saved because the event file's drive or folder
/// has gone: a pulled USB stick, a dropped network share.
class EventFileUnreachable extends TournamentException {
  const EventFileUnreachable()
    : super(
        'The drive or folder holding this event can no longer be reached, so '
        'this change was not saved. Reconnect it and reopen the event, or save '
        'a copy somewhere else and carry on in the copy.',
      );
}

abstract interface class EventRepository {
  Event? load();

  /// Saves [next] as the next revision. A change to nothing but where backups
  /// go is saved and logged without adding a point to the history, because
  /// that is a setting of this computer, not part of the tournament.
  Event commit(
    Event next, {
    required int expectedRevision,
    required String action,
  });

  /// Moves the event to the saved state of history [node]. The revision still
  /// advances, so proposals made against the previous state stay stale. The
  /// backup folder stays as it is now: history never changes it.
  Event checkout(
    int node, {
    required int expectedRevision,
    required String action,
  });
  HistoryGraph historyGraph();
  Event snapshot(int node);
  List<Json> history();

  /// When the event was last saved: the newest audit row, which a history
  /// move writes too. Null before the first save.
  String? lastSaved();
  String? readPreference(String key);
  void writePreference(String key, String value);

  /// Forgets a preference, so reading it gives null again.
  void deletePreference(String key);

  /// Whether the event's file is still where it was opened, checked now.
  /// Null while it is.
  EventFileProblem? checkFile();

  /// [replaceExisting] is reserved for user-confirmed native Save dialogs.
  /// When the event's own file can no longer be read, the copy holds the
  /// event as last saved without its earlier history.
  void backup(String destination, {bool replaceExisting = false});

  /// A verified, independently openable copy of the event as bytes, for the
  /// browser version's downloads.
  List<int> snapshotBytes();
  void close();
}

/// Whether going from [before] to [after] changes only where backups go.
bool backupSettingsOnly(Event before, Event after) =>
    (before.backupFolder != after.backupFolder ||
        before.lastBackupRevision != after.lastBackupRevision) &&
    tournamentContent(before) == tournamentContent(after);
