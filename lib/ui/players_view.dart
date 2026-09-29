import 'dart:convert';
import 'package:flutter/material.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../infrastructure/roster_import.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'identity_review.dart';

Future<void> editPlayer(
  BuildContext context,
  TournamentController c, {
  Player? player,
}) async {
  final draftKey = 'player-draft-${player?.id ?? 'new'}';
  final saved = c.repository.readPreference(draftKey);
  final values = saved != null && saved.isNotEmpty
      ? Map<String, String>.from(jsonDecode(saved))
      : {
          'name': player?.name ?? '',
          'memberId': player?.memberId ?? '',
          'rating': '${player?.rating ?? 0}',
          'club': player?.club ?? '',
          'notes': player?.notes ?? '',
        };
  await editFields(
    context,
    title: player == null ? 'Register a player' : 'Edit ${player.name}',
    values: values,
    description:
        'Ratings are assigned pairing values. US Chess IDs are retained as entered until verified.',
    fields: const [
      FieldSpec('name', 'Full name', required: true),
      FieldSpec('memberId', 'US Chess ID (optional)'),
      FieldSpec('rating', 'Pairing rating · 0 for unrated', required: true),
      FieldSpec('club', 'Team / club'),
      FieldSpec('notes', 'Private notes', lines: 3),
    ],
    onDraft: (v) => c.repository.writePreference(draftKey, jsonEncode(v)),
    onSave: (v) {
      final rating = int.tryParse(v['rating']!);
      if (rating == null) {
        throw const TournamentException('Enter a whole-number rating.');
      }
      c.savePlayer(
        (player ?? Player(id: c.newId(), name: '')).copy(
          name: v['name']!.trim(),
          memberId: v['memberId']!.trim(),
          rating: rating,
          club: v['club']!.trim(),
          notes: v['notes']!,
        ),
      );
      c.repository.writePreference(draftKey, '');
    },
  );
}

Future<void> importRoster(BuildContext context, TournamentController c) async {
  final text = c.repository.readPreference('import-draft') ?? '';
  final input = await editFields(
    context,
    title: 'Import a roster',
    saveLabel: 'Preview import',
    description:
        'Paste CSV or a spreadsheet table. Headers: Name, US Chess ID, Rating, Club. Existing names and IDs are preserved on re-import.',
    fields: const [
      FieldSpec(
        'roster',
        'Roster',
        lines: 12,
        required: true,
        hint: 'Name,ID,Rating\nMorgan Lee,12345678,1650',
      ),
    ],
    values: {'roster': text},
    onDraft: (v) => c.repository.writePreference('import-draft', v['roster']!),
  );
  if (input == null || !context.mounted) return;
  try {
    final rows = parseRoster(input['roster']!);
    final valid = rows.where((r) => r.player != null).toList();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${valid.length} ready · ${rows.length - valid.length} need repair',
        ),
        content: SizedBox(
          width: 660,
          height: 360,
          child: ListView(
            children: [
              for (final r in rows)
                ListTile(
                  leading: Icon(
                    r.error == null
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                  ),
                  title: Text(r.player?.name ?? 'Row ${r.line}'),
                  subtitle: Text(
                    r.error ??
                        'ID ${r.player!.memberId.isEmpty ? 'not supplied' : r.player!.memberId} · ${r.player!.rating}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: valid.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: Text('Import ${valid.length} ready rows'),
          ),
        ],
      ),
    );
    if (accepted == true) c.importPlayers(valid.map((r) => r.player!).toList());
  } catch (e) {
    if (context.mounted) showFailure(context, e);
  }
}

class PlayersView extends StatefulWidget {
  const PlayersView({
    required this.controller,
    this.sectionId,
    this.checkIn = false,
    super.key,
  });
  final TournamentController controller;
  final String? sectionId;
  final bool checkIn;
  @override
  State<PlayersView> createState() => _PlayersViewState();
}

class _PlayersViewState extends State<PlayersView> {
  final search = TextEditingController();
  bool absentOnly = false;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> action(Player player, String value) async {
    final c = widget.controller;
    try {
      switch (value) {
        case 'edit':
          await editPlayer(context, c, player: player);
        case 'identity':
          await checkIdentity(context, c, player);
        case 'withdraw':
          c.savePlayer(player.copy(withdrawn: !player.withdrawn));
        case 'bye':
          await editFields(
            context,
            title: 'Byes · ${player.name}',
            description:
                'Future rounds only. Points: 0, 0.5 or 1. Use “cancel” to remove a reservation.',
            fields: const [
              FieldSpec('round', 'Round', required: true),
              FieldSpec('score', 'Points', required: true),
            ],
            values: {
              'round':
                  '${(c.event!.sectionOf(player.id)?.rounds.length ?? 0) + 1}',
              'score': '0.5',
            },
            onSave: (v) {
              final round = int.tryParse(v['round']!);
              final score = switch (v['score']!.trim()) {
                '0' => 0,
                '0.5' || '½' => 1,
                '1' => 2,
                'cancel' => -1,
                _ => null,
              };
              if (round == null || round < 1 || score == null) {
                throw const TournamentException(
                  'Enter a valid round and 0, 0.5, 1 or cancel.',
                );
              }
              c.reserveBye(player.id, round, score);
            },
          );
        case 'move':
          final target = await showDialog<String>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('Move to section'),
              children: [
                for (final s in c.event!.sections.where(
                  (s) => !s.players.contains(player.id),
                ))
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, s.id),
                    child: Text(s.name),
                  ),
              ],
            ),
          );
          if (target != null && mounted) {
            await editFields(
              context,
              title: 'Review section transfer',
              description:
                  'Points, opponent history and played games are retained. The destination becomes Swiss. Post-play rating mapping is not yet externally validated.',
              fields: const [FieldSpec('reason', 'Reason')],
              onSave: (v) =>
                  c.movePlayers([player.id], target, reason: v['reason']!),
            );
          }
      }
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, e = c.event!;
    final players = e.players
        .where(
          (p) =>
              (widget.sectionId == null ||
                  e.sectionOf(p.id)?.id == widget.sectionId) &&
              (!absentOnly || !p.checkedIn) &&
              (p.name.toLowerCase().contains(search.text.toLowerCase()) ||
                  p.memberId.contains(search.text)),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  key: const ValueKey('player-search'),
                  controller: search,
                  autofocus: widget.checkIn,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: widget.checkIn
                        ? 'Find a player · Enter to check in'
                        : 'Search name or US Chess ID',
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (players.isNotEmpty) {
                      try {
                        c.savePlayer(players.first.copy(checkedIn: true));
                        search.clear();
                        setState(() {});
                      } catch (e) {
                        showFailure(context, e);
                      }
                    }
                  },
                ),
              ),
              FilterChip(
                label: const Text('Not yet here'),
                selected: absentOnly,
                onSelected: (v) => setState(() => absentOnly = v),
              ),
              FilledButton.icon(
                onPressed: () => editPlayer(context, c),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add player'),
              ),
              OutlinedButton.icon(
                onPressed: () => importRoster(context, c),
                icon: const Icon(Icons.upload_file),
                label: const Text('Import roster'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            '${players.length} entries · ${e.players.where((p) => p.checkedIn).length} checked in · Double-click a name to edit',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: players.isEmpty
              ? EmptyState(
                  icon: Icons.people_outline,
                  title: 'The room starts here',
                  body:
                      'Import your registrations or add a walk-up. Names, ratings and private notes stay in this event.',
                  action: TextButton(
                    onPressed: () => importRoster(context, c),
                    child: const Text('Paste a roster'),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Here')),
                            DataColumn(label: Text('Player')),
                            DataColumn(label: Text('Rating'), numeric: true),
                            DataColumn(label: Text('Section')),
                            DataColumn(label: Text('US Chess ID')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('')),
                          ],
                          rows: [
                            for (final p in players)
                              DataRow(
                                cells: [
                                  DataCell(
                                    Checkbox(
                                      value: p.checkedIn,
                                      onChanged: (v) {
                                        try {
                                          c.savePlayer(p.copy(checkedIn: v!));
                                        } catch (e) {
                                          showFailure(context, e);
                                        }
                                      },
                                    ),
                                  ),
                                  DataCell(
                                    GestureDetector(
                                      onDoubleTap: () =>
                                          editPlayer(context, c, player: p),
                                      child: TextButton(
                                        onPressed: () =>
                                            editPlayer(context, c, player: p),
                                        child: Text(p.name),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      p.rating == 0 ? 'Unrated' : '${p.rating}',
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      e.sectionOf(p.id)?.name ?? 'Unassigned',
                                    ),
                                  ),
                                  DataCell(
                                    Text(p.memberId.isEmpty ? '—' : p.memberId),
                                  ),
                                  DataCell(
                                    StatusPill(
                                      p.withdrawn
                                          ? 'Withdrawn'
                                          : p.checkedIn
                                          ? 'Present'
                                          : 'Expected',
                                      good: p.checkedIn && !p.withdrawn,
                                    ),
                                  ),
                                  DataCell(
                                    PopupMenuButton<String>(
                                      tooltip: 'Player actions',
                                      onSelected: (v) => action(p, v),
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit player'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'identity',
                                          child: Text('Check US Chess ID'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'bye',
                                          child: Text('Byes'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'move',
                                          child: Text('Move section'),
                                        ),
                                        PopupMenuItem(
                                          value: 'withdraw',
                                          child: Text(
                                            p.withdrawn
                                                ? 'Reinstate'
                                                : 'Withdraw',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
