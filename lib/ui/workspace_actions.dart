import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../infrastructure/sqlite_event_repository.dart';
import 'dialogs.dart';

/// Dialog workflows use the same application commands as keyboard entry.
class WorkspaceActions {
  const WorkspaceActions(this.context, this.c);
  final BuildContext context;
  final TournamentController c;
  Future<void> settings() async {
    final e = c.event!;
    await editFields(
      context,
      title: 'Event settings',
      fields: const [
        FieldSpec('name', 'Event name', required: true),
        FieldSpec('date', 'Date (YYYY-MM-DD)', required: true),
        FieldSpec('time', 'Time control', hint: 'G/60;d5'),
        FieldSpec('venue', 'Venue or city'),
        FieldSpec('td', 'Chief TD US Chess ID'),
        FieldSpec('affiliate', 'Affiliate ID'),
        FieldSpec('policy', 'Announced conditions', lines: 3),
        FieldSpec('notes', 'Private TD notes', lines: 4),
      ],
      values: {
        'name': e.name,
        'date': e.date,
        'time': e.timeControl,
        'venue': e.venue,
        'td': e.tdId,
        'affiliate': e.affiliateId,
        'policy': e.policy,
        'notes': e.notes,
      },
      onSave: (v) {
        final date = DateTime.tryParse(v['date']!);
        if (date == null ||
            date.toIso8601String().substring(0, 10) != v['date']) {
          throw const TournamentException('Use a valid YYYY-MM-DD date.');
        }
        c.change(
          'Edit event settings',
          c.event!.copy(
            name: v['name'],
            date: v['date'],
            timeControl: v['time'],
            venue: v['venue'],
            tdId: v['td'],
            affiliateId: v['affiliate'],
            policy: v['policy'],
            notes: v['notes'],
          ),
        );
      },
    );
  }

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

  /// Chooses a tournament type and creates its sections. Returns true when
  /// sections changed.
  Future<bool> addSections() async {
    final e = c.event!;
    final free = e.players
        .where((p) => e.sectionOf(p.id) == null && !p.withdrawn)
        .length;
    final type = await openDialog<Format>(
      context: context,
      builder: (context) {
        Widget option(Format f, IconData icon, String title, String body) =>
            Card(
              child: ListTile(
                key: ValueKey('type-${f.name}'),
                leading: Icon(icon),
                title: Text(title),
                subtitle: Text(body),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, f),
              ),
            );
        return SimpleDialog(
          title: const Text('Create sections'),
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            SizedBox(
              width: 520,
              child: Column(
                children: [
                  option(
                    Format.quad,
                    Icons.grid_view,
                    'Quads',
                    'Split all players by rating into groups of four. Leftovers play a small Swiss.',
                  ),
                  option(
                    Format.swiss,
                    Icons.shuffle,
                    'Swiss',
                    'One section. Players meet opponents with the same score each round.',
                  ),
                  option(
                    Format.roundRobin,
                    Icons.sync_alt,
                    'Round robin',
                    'One section. Everyone plays everyone.',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (type == null || !context.mounted) return false;
    if (type == Format.quad) return makeQuads();
    final robin = type == Format.roundRobin;
    final result = await editFields(
      context,
      title: robin ? 'New round robin' : 'New Swiss section',
      description: free == 0
          ? 'Every player is already in a section. The new section starts empty; move players into it from the Players page.'
          : 'The $free ${free == 1 ? 'player' : 'players'} not yet in a section will be added.',
      fields: [
        const FieldSpec('name', 'Section name', required: true),
        const FieldSpec('rounds', 'Number of rounds', required: true),
        if (robin)
          const FieldSpec(
            'double',
            'Games per pairing',
            options: {'no': 'One game', 'yes': 'Two games (double round)'},
          ),
      ],
      values: {
        'name': robin ? 'Round robin' : 'Open',
        'rounds': robin
            ? '${free < 2
                  ? 1
                  : free.isEven
                  ? free - 1
                  : free}'
            : '4',
        'double': 'no',
      },
      onSave: (v) {
        final rounds = int.tryParse(v['rounds']!);
        if (rounds == null || rounds < 1 || rounds > 32) {
          throw const TournamentException(
            'Number of rounds must be between 1 and 32.',
          );
        }
        c.addSection(
          v['name']!.trim(),
          type,
          rounds,
          doubleGames: v['double'] == 'yes',
        );
      },
    );
    return result != null;
  }

  Future<bool> makeQuads() async {
    try {
      final revision = c.event!.revision, groups = c.quadPreview();
      final replacing = c.event!.sections.any((s) => s.players.isNotEmpty);
      final yes = await openDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Make quads'),
          content: SizedBox(
            width: 620,
            height: 420,
            child: ListView(
              children: [
                Text(
                  'Players are grouped by rating, highest first. Withdrawn players are left out.'
                  '${replacing ? ' This replaces the current sections.' : ''}',
                ),
                const SizedBox(height: 16),
                for (final s in groups)
                  ListTile(
                    title: Text('${s.name} · ${s.players.length} players'),
                    subtitle: Text(
                      s.players
                          .map(
                            (id) =>
                                '${c.event!.player(id).name} (${c.event!.player(id).rating})',
                          )
                          .join('\n'),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Create ${groups.length} sections'),
            ),
          ],
        ),
      );
      if (yes != true) return false;
      c.applyQuads(groups, revision);
      return true;
    } catch (e) {
      if (context.mounted) showFailure(context, e);
      return false;
    }
  }

  Future<void> sectionSettings(String sectionId) async {
    final s = c.event!.sections.firstWhere((s) => s.id == sectionId);
    await editFields(
      context,
      title: '${s.name} settings',
      description: 'A new first board number applies from the next round.',
      fields: const [
        FieldSpec('name', 'Name', required: true),
        FieldSpec('rounds', 'Number of rounds', required: true),
        FieldSpec('board', 'First board number', required: true),
      ],
      values: {
        'name': s.name,
        'rounds': '${s.plannedRounds}',
        'board': '${s.boardStart}',
      },
      onSave: (v) {
        final rounds = int.tryParse(v['rounds']!),
            board = int.tryParse(v['board']!);
        if (rounds == null ||
            rounds < s.rounds.length ||
            rounds < 1 ||
            rounds > 32 ||
            board == null ||
            board < 1) {
          throw const TournamentException(
            'Check the number of rounds and the board number.',
          );
        }
        c.change(
          'Edit section ${s.name}',
          c.event!.copy(
            sections: c.event!.sections
                .map(
                  (x) => x.id == s.id
                      ? x.copy(
                          name: v['name'],
                          plannedRounds: rounds,
                          boardStart: board,
                        )
                      : x,
                )
                .toList(),
          ),
        );
      },
    );
  }

  Future<void> combine(String sectionId) async {
    final source = c.event!.sections.firstWhere((s) => s.id == sectionId);
    final target = await openDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Combine ${source.name} into…'),
        children: [
          for (final s in c.event!.sections.where((s) => s.id != source.id))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, s.id),
              child: Text('${s.name} · ${s.players.length} players'),
            ),
        ],
      ),
    );
    if (target != null && context.mounted) {
      await editFields(
        context,
        title: 'Combine sections',
        description:
            'Moves all ${source.players.length} players into the other section, which will use Swiss pairings. Games and points already played are kept. Both sections must have played the same number of rounds.',
        fields: const [FieldSpec('reason', 'Reason (optional)')],
        onSave: (v) =>
            c.movePlayers(source.players, target, reason: v['reason']!),
      );
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

  Future<void> editPairing(String sectionId) async {
    final s = c.event!.sections.firstWhere((s) => s.id == sectionId);
    if (s.rounds.isEmpty) return;
    final r = s.rounds.last;
    if (r.hasPlay) {
      showFailure(
        context,
        'Pairings can’t be edited after a game in the round has a result.',
      );
      return;
    }
    await editFields(
      context,
      title: 'Edit pairings',
      description:
          'One line per game: board, White player number, Black player number. Every player must still be paired.\n\n${s.players.indexed.map((v) => '${v.$1 + 1}. ${c.event!.player(v.$2).name}').join('\n')}',
      fields: const [
        FieldSpec('games', 'Pairings', lines: 6, required: true),
        FieldSpec('reason', 'Reason', required: true),
      ],
      values: {
        'games': r.games
            .map(
              (g) =>
                  '${g.board},${s.players.indexOf(g.white) + 1},${s.players.indexOf(g.black) + 1}',
            )
            .join('\n'),
      },
      onSave: (v) {
        final lines = v['games']!.trim().split('\n');
        if (lines.length != r.games.length) {
          throw const TournamentException('Keep the same number of games.');
        }
        final games = <Game>[];
        for (final (i, line) in lines.indexed) {
          final parts = line
              .split(',')
              .map((v) => int.tryParse(v.trim()))
              .toList();
          if (parts.length != 3 ||
              parts.any((v) => v == null) ||
              parts[1]! < 1 ||
              parts[1]! > s.players.length ||
              parts[2]! < 1 ||
              parts[2]! > s.players.length) {
            throw const TournamentException(
              'Each line needs: board, White number, Black number.',
            );
          }
          games.add(
            r.games[i].copy(
              board: parts[0],
              white: s.players[parts[1]! - 1],
              black: s.players[parts[2]! - 1],
            ),
          );
        }
        c.replacePairing(s.id, r.number, games, v['reason']!);
      },
    );
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
