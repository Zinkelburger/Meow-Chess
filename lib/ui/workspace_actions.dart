import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../application/tournament_controller.dart';
import '../application/diagnostics.dart';
import '../infrastructure/save_location.dart';
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

  Future<String?> saveCopy() async {
    String? destination;
    try {
      final location = await chooseSaveLocation(
        suggestedName: 'event-r${c.event!.revision}.meow',
      );
      if (location == null) return null;
      destination = location.path;
      c.repository.backup(location.path, replaceExisting: true);
      Diagnostics.record(
        'save event copy',
        'succeeded',
        context: {'path': destination},
      );
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
