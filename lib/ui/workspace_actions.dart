import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
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

  Future<void> lookup() async {
    await openDialog<void>(
      context: context,
      builder: (context) => _Lookup(event: c.event!),
    );
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

class _Lookup extends StatefulWidget {
  const _Lookup({required this.event});
  final Event event;
  @override
  State<_Lookup> createState() => _LookupState();
}

class _LookupState extends State<_Lookup> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final players = e.players
        .where(
          (p) =>
              query.isNotEmpty &&
              (p.name.toLowerCase().contains(query.toLowerCase()) ||
                  p.memberId == query ||
                  '${(e.sectionOf(p.id)?.players.indexOf(p.id) ?? -1) + 1}' ==
                      query),
        )
        .toList();
    return AlertDialog(
      title: const Text('Find player'),
      content: SizedBox(
        width: 680,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Name, US Chess ID or player number',
              ),
              onChanged: (v) => setState(() => query = v),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  for (final p in players)
                    Builder(
                      builder: (context) {
                        final s = e.sectionOf(p.id),
                            g = s?.rounds.lastOrNull?.games
                                .where(
                                  (g) => g.white == p.id || g.black == p.id,
                                )
                                .firstOrNull;
                        return ListTile(
                          title: Text(
                            p.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          subtitle: Text(
                            '${s?.name ?? 'No section'} · ${g == null ? 'No current game' : 'Board ${g.board} · ${g.white == p.id ? 'White' : 'Black'} vs ${e.player(g.white == p.id ? g.black : g.white).name}'}${p.byes.isEmpty ? '' : '\nByes: ${p.byes.entries.map((b) => 'Round ${b.key} (${scoreText(b.value)})').join(', ')}'}',
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
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
