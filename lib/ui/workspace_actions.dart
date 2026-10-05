import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../application/tournament_controller.dart';
import '../application/diagnostics.dart';
import '../infrastructure/save_location.dart';
import '../infrastructure/event_save.dart';
import '../infrastructure/file_access.dart';
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
      final remembered = await rememberFileAccess(folder);
      if (!context.mounted) return;
      c.change('Set backup folder', c.event!.copy(backupFolder: folder));
      c.secondaryBackup();
      if (!remembered && context.mounted) {
        showFailure(
          context,
          'The backup folder works for this session, but its access could not be remembered. Select it again after restarting.',
        );
      }
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

  Future<String?> saveCopy() async {
    String? destination;
    try {
      final location = await chooseSaveLocation(
        suggestedName: 'event-r${c.event!.revision}.meow',
      );
      if (location == null) return null;
      destination = location.path;
      await saveSelectedEvent(c.repository, location.path);
      Diagnostics.record(
        'save event copy',
        'succeeded',
        context: {'path': destination},
      );
      final remembered = await rememberFileAccess(location.path);
      if (!remembered && context.mounted) {
        showFailure(
          context,
          'The copy was saved, but its access could not be remembered. Select it with Open event after restarting.',
        );
      }
      return location.path;
    } catch (e, stack) {
      Diagnostics.record(
        'save event copy',
        'failed',
        error: e,
        stack: stack,
        context: {'path': ?destination},
      );
      if (context.mounted) showFailure(context, e);
      return null;
    }
  }
}
