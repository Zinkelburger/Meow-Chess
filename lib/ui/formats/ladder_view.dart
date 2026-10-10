import 'package:flutter/material.dart';

import '../../application/failures.dart';
import '../../application/tournament_controller.dart';
import '../../application/tournament_controller_core.dart' show LadderCommands;
import '../../domain/ladder.dart';
import '../../domain/model.dart';
import '../dialogs.dart' show showFailure;
import '../pane_controls.dart';
import '../select.dart';
import '../theme.dart';

/// The ladder as a ruled table, top down, with the one thing a director does
/// here on a row above it: record a challenge. Recording applies at once and
/// confirms in place with Undo; there are no rounds to create.
class LadderView extends StatefulWidget {
  const LadderView({
    required this.controller,
    required this.section,
    super.key,
  });
  final TournamentController controller;
  final Section section;

  @override
  State<LadderView> createState() => _LadderViewState();
}

class _LadderViewState extends State<LadderView> {
  String? challenger, defender, error;
  ChallengeResult? result;
  bool challengerWhite = false;

  /// The history node a recording left, so Undo is offered only while the
  /// ladder is still exactly as that recording left it.
  int? doneHead;
  String? doneMessage;

  TournamentController get c => widget.controller;
  Section get section => widget.section;

  bool get ready => challenger != null && defender != null && result != null;

  void record() {
    final e = c.event!;
    String name(String id) => e.player(id).name;
    final before = section.players;
    try {
      c.recordLadderGame(
        section.id,
        challenger!,
        defender!,
        result!.outcome(challengerWhite: challengerWhite),
        challengerWhite: challengerWhite,
      );
    } catch (error) {
      setState(() => this.error = plainMessage(error));
      return;
    }
    final after = c.event!.sections
        .firstWhere((s) => s.id == section.id)
        .players;
    final who = name(challenger!);
    final place = after.indexOf(challenger!) + 1;
    setState(() {
      doneHead = c.graph.head;
      doneMessage = after.indexOf(challenger!) == before.indexOf(challenger!)
          ? '$who stays at #$place'
          : '$who moves to #$place';
      error = null;
      challenger = defender = null;
      result = null;
      challengerWhite = false;
    });
  }

  void undo() {
    try {
      // The line says what Undo takes back: the challenge just recorded.
      c.undo(acceptLosses: true);
      setState(() {
        doneHead = null;
        doneMessage = null;
      });
    } catch (error) {
      showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = c.event!;
    final colors = Theme.of(context).colorScheme;
    String name(String id) => e.player(id).name;
    final active = [
      for (final id in section.players)
        if (!e.player(id).withdrawn) id,
    ];
    if (challenger != null && !active.contains(challenger)) {
      challenger = null;
    }
    final defenders = challenger == null
        ? const <String>[]
        : ladderDefenders(section, challenger!).where(active.contains).toList();
    if (defender != null && !defenders.contains(defender)) defender = null;
    final canUndo = doneHead != null && c.graph.head == doneHead;
    String labelled(String id) => '#${ladderPosition(section, id)} ${name(id)}';

    final heading = PaneHeading(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Ladder · ${section.players.length} players',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text:
                  '   Challenge up to $ladderChallengeRange places above; a win takes the place'
                  '${section.unrated ? ' · Not rated' : ''}',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );

    final recordRow = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: PlainSelect<String?>(
              key: const ValueKey('ladder-challenger'),
              label: 'Challenger',
              hint: 'Choose a player',
              value: challenger,
              options: [
                for (final id in active) SelectOption(id, labelled(id)),
              ],
              onChanged: (v) => setState(() {
                challenger = v;
                error = null;
              }),
            ),
          ),
          SizedBox(
            width: 240,
            child: PlainSelect<String?>(
              key: const ValueKey('ladder-defender'),
              label: 'Challenges',
              hint: challenger == null
                  ? 'Choose the challenger first'
                  : defenders.isEmpty
                  ? 'Nobody to challenge'
                  : 'Choose a player above',
              value: defender,
              options: [
                for (final id in defenders) SelectOption(id, labelled(id)),
              ],
              onChanged: defenders.isEmpty
                  ? null
                  : (v) => setState(() {
                      defender = v;
                      error = null;
                    }),
            ),
          ),
          SegmentedButton<ChallengeResult>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(
                value: ChallengeResult.win,
                label: Text('1–0', key: ValueKey('ladder-result-win')),
                tooltip: 'Challenger wins',
              ),
              ButtonSegment(
                value: ChallengeResult.draw,
                label: Text('½–½', key: ValueKey('ladder-result-draw')),
                tooltip: 'Draw',
              ),
              ButtonSegment(
                value: ChallengeResult.loss,
                label: Text('0–1', key: ValueKey('ladder-result-loss')),
                tooltip: 'Challenger loses',
              ),
            ],
            selected: {?result},
            onSelectionChanged: (v) => setState(() {
              result = v.firstOrNull;
              error = null;
            }),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlainCheckbox(
                key: const ValueKey('ladder-challenger-white'),
                label: 'Challenger has White',
                value: challengerWhite,
                onChanged: (v) => setState(() => challengerWhite = v == true),
              ),
              const SizedBox(width: 6),
              const Text('Challenger has White'),
            ],
          ),
          FilledButton(
            key: const ValueKey('ladder-record'),
            onPressed: ready ? record : null,
            child: const Text('Record'),
          ),
        ],
      ),
    );

    final notice = error != null
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(error!, style: TextStyle(color: colors.error)),
          )
        : doneMessage != null
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: colors.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(doneMessage!),
                  if (canUndo)
                    TextButton(
                      key: const ValueKey('ladder-undo'),
                      onPressed: undo,
                      child: const Text('Undo'),
                    ),
                ],
              ),
            ),
          )
        : const SizedBox.shrink();

    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    Widget cell(double width, String text, {bool center = false}) => SizedBox(
      width: width * scale,
      child: Text(
        text,
        textAlign: center ? TextAlign.center : null,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final header = Container(
      key: const ValueKey('ladder-column-header'),
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
        child: Row(
          children: [
            cell(40, '#'),
            const Expanded(flex: 3, child: Text('Name')),
            cell(60, 'Rating', center: true),
            cell(60, 'Games', center: true),
            const Expanded(flex: 2, child: Text('Last result')),
          ],
        ),
      ),
    );
    Widget row(int index, String id) {
      final p = e.player(id);
      final muted = TextStyle(color: colors.onSurfaceVariant);
      return Container(
        key: ValueKey('ladder-row-$id'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: DefaultTextStyle.merge(
          style: p.withdrawn ? muted : null,
          child: Row(
            children: [
              cell(40, '${index + 1}'),
              Expanded(
                flex: 3,
                child: Text(
                  p.withdrawn ? '${p.name} · withdrawn' : p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              cell(60, p.rating == 0 ? 'UNR' : '${p.rating}', center: true),
              cell(60, '${ladderGames(section, id).length}', center: true),
              Expanded(
                flex: 2,
                child: Text(
                  ladderLastResult(section, id, name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        recordRow,
        notice,
        if (section.players.isEmpty)
          const Expanded(
            child: EmptyState(
              icon: Icons.format_list_numbered,
              title: 'Nobody on the ladder',
              body: 'Move players into this section to start the ladder.',
            ),
          )
        else
          Expanded(
            child: ListView(
              key: const ValueKey('ladder-table'),
              children: [
                header,
                for (final (i, id) in section.players.indexed) row(i, id),
              ],
            ),
          ),
      ],
    );
  }
}
