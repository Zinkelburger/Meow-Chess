import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../application/tournament_controller.dart';
import '../infrastructure/sqlite_event_repository.dart';
import 'dialogs.dart';

/// Event-level actions shared by the toolbar and the event panel.
class WorkspaceActions {
  const WorkspaceActions(this.context, this.c);
  final BuildContext context;
  final TournamentController c;
  Future<void> chooseBackupFolder() async {
    try {
      final folder = await getDirectoryPath(
        confirmButtonText: 'Back up here',
        initialDirectory: c.event!.backupFolder.isEmpty
            ? null
            : c.event!.backupFolder,
      );
      if (folder == null) return;
      c.change('Set backup folder', c.event!.copy(backupFolder: folder));
      c.secondaryBackup();
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  void clearBackupFolder() {
    try {
      c.change('Stop folder backups', c.event!.copy(backupFolder: ''));
    } catch (e) {
      showFailure(context, e);
    }
  }

  Future<void> saveCopy({bool practice = false}) async {
    try {
      final location = await getSaveLocation(
        suggestedName: practice
            ? 'practice.meow'
            : 'event-r${c.event!.revision}.meow',
      );
      if (location == null) return;
      c.repository.backup(location.path);
      if (practice) {
        // Opening a separate connection is safe: this is an independent snapshot.
        await _markPractice(location.path);
      }
      if (context.mounted) {
        showNotice(
          context,
          '${practice ? 'Practice copy' : 'Copy'} saved to ${location.path}',
        );
      }
    } catch (e) {
      if (context.mounted) showFailure(context, e);
    }
  }

  Future<void> _markPractice(String path) async {
    await markPracticeCopy(path);
  }
}

Future<void> markPracticeCopy(String path) async {
  final repository = SqliteEventRepository(path);
  try {
    final event = repository.load()!;
    repository.commit(
      event.copy(practice: true, backupFolder: ''),
      expectedRevision: event.revision,
      action: 'Mark practice copy',
    );
  } finally {
    repository.close();
  }
}
