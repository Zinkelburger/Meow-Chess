import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
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
      description:
          'Changes are recorded in history. Played games and posted pairings are retained. Tie-break computation in this pilot remains points, played-opponent Buchholz, then Sonneborn–Berger.',
      fields: const [
        FieldSpec('name', 'Event name', required: true),
        FieldSpec('date', 'Event date · YYYY-MM-DD', required: true),
        FieldSpec('time', 'Time control'),
        FieldSpec('venue', 'Venue / city'),
        FieldSpec('td', 'Chief TD ID'),
        FieldSpec('affiliate', 'Affiliate ID'),
        FieldSpec('backup', 'Secondary backup folder'),
        FieldSpec('policy', 'Announced conditions', lines: 3),
        FieldSpec('notes', 'Private TD notes / rulings / handover', lines: 4),
      ],
      values: {
        'name': e.name,
        'date': e.date,
        'time': e.timeControl,
        'venue': e.venue,
        'td': e.tdId,
        'affiliate': e.affiliateId,
        'backup': e.backupFolder,
        'policy': e.policy,
        'notes': e.notes,
      },
      onSave: (v) {
        final date = DateTime.tryParse(v['date']!);
        if (date == null ||
            date.toIso8601String().substring(0, 10) != v['date']) {
          throw const TournamentException('Use a valid YYYY-MM-DD date.');
        }
        if (v['backup']!.isNotEmpty && !p.isAbsolute(v['backup']!)) {
          throw const TournamentException(
            'Use an absolute backup folder path.',
          );
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
            backupFolder: v['backup'],
            policy: v['policy'],
            notes: v['notes'],
          ),
        );
      },
    );
  }

  Future<void> newSection() async {
    await editFields(
      context,
      title: 'Create a section',
      description:
          'Currently unassigned players enter this section. Formats: swiss, quad, roundRobin. Swiss uses a pilot pairing policy pending rule qualification.',
      fields: const [
        FieldSpec('name', 'Section name', required: true),
        FieldSpec('format', 'Format', required: true),
        FieldSpec('rounds', 'Planned rounds', required: true),
        FieldSpec('double', 'Double games · yes / no'),
      ],
      values: const {
        'name': 'Open',
        'format': 'swiss',
        'rounds': '3',
        'double': 'no',
      },
      onSave: (v) {
        final format = Format.values
                .where((f) => f.name == v['format'])
                .firstOrNull,
            rounds = int.tryParse(v['rounds']!);
        if (format == null || rounds == null || rounds < 1 || rounds > 32) {
          throw const TournamentException(
            'Choose a listed format and 1–32 rounds.',
          );
        }
        c.addSection(
          v['name']!,
          format,
          rounds,
          doubleGames: v['double']!.toLowerCase() == 'yes',
        );
      },
    );
  }

  Future<void> sectionSettings(String sectionId) async {
    final s = c.event!.sections.firstWhere((s) => s.id == sectionId);
    await editFields(
      context,
      title: '${s.name} settings',
      description:
          'Board ranges apply to future rounds. Existing posted games keep their boards.',
      fields: const [
        FieldSpec('name', 'Name', required: true),
        FieldSpec('rounds', 'Planned rounds', required: true),
        FieldSpec('board', 'First board', required: true),
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
            'Invalid round count or board number.',
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
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Combine ${source.name} with…'),
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
        title: 'Review combination',
        description:
            'Move ${source.players.length} players into the destination Swiss pool. All played games, points, opponent history and original attribution remain. Both sections must be between rounds with equal progress. Review prize policy separately; post-play reporting mapping is unverified.',
        fields: const [FieldSpec('reason', 'Reason / prize policy decision')],
        onSave: (v) =>
            c.movePlayers(source.players, target, reason: v['reason']!),
      );
    }
  }

  Future<void> lookup() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _Lookup(event: c.event!),
    );
  }

  Future<void> history() async => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Event history'),
      content: SizedBox(
        width: 660,
        height: 460,
        child: ListView(
          children: [
            for (final h in c.repository.history())
              ListTile(
                title: Text(h['action']),
                subtitle: Text('Revision ${h['revision']} · ${h['timestamp']}'),
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
    ),
  );
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
        showFailure(
          context,
          'Independent ${practice ? 'practice ' : ''}copy saved: ${location.path}',
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
        'This round has started. Its participants must be preserved.',
      );
      return;
    }
    await editFields(
      context,
      title: 'Replace posted pairings',
      description:
          'Confirm no affected game has started. Enter one line per game: board, White entry number, Black entry number. Entry numbers below are section pairing numbers. All existing participants must remain.\n${s.players.indexed.map((v) => '${v.$1 + 1}: ${c.event!.player(v.$2).name}').join('\n')}',
      fields: const [
        FieldSpec('games', 'Pairings', lines: 6, required: true),
        FieldSpec(
          'reason',
          'Confirm games not started; reason',
          required: true,
        ),
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
              'Use board, White number, Black number on each line.',
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
      title: const Text('Player lookup · read only'),
      content: SizedBox(
        width: 680,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Name, ID or section pairing number',
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
                            '${s?.name ?? 'Unassigned'} · ${g == null ? 'No current game' : 'Board ${g.board} · ${g.white == p.id ? 'White' : 'Black'} vs ${e.player(g.white == p.id ? g.black : g.white).name}'}\nByes: ${p.byes.entries.map((b) => 'R${b.key}: ${scoreText(b.value)}').join(', ')}',
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
