import 'package:flutter/material.dart';

import '../domain/model.dart';
import '../infrastructure/reports.dart';
import 'panels.dart' show printSheets;
import 'player_format.dart';
import 'result_format.dart';

/// A compact wall sheet of each section's latest posted round.
class CurrentPairings extends StatelessWidget {
  const CurrentPairings({
    required this.event,
    required this.onPlayer,
    this.sectionId,
    super.key,
  });

  final Event event;
  final String? sectionId;
  final ValueChanged<String> onPlayer;

  @override
  Widget build(BuildContext context) {
    final sections = event.sections
        .where((s) => sectionId == null || s.id == sectionId)
        .toList();
    final hasRounds = sections.any((s) => s.rounds.isNotEmpty);
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('pairings-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Pairings', style: Theme.of(context).textTheme.titleLarge),
              OutlinedButton.icon(
                key: const ValueKey('print-pairings'),
                onPressed: !hasRounds
                    ? null
                    : () => printSheets(
                        context,
                        event,
                        sectionId: sectionId,
                        kind: ReportKind.pairings,
                        currentRoundOnly: true,
                      ),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print pairings'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            key: const PageStorageKey('current-pairings-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              for (final section in sections) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  color: colors.surfaceContainerLow,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (section.rounds.lastOrNull case final round?) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Round ${round.number} · '
                          '${round.games.where((g) => g.outcome.resolved).length}'
                          ' of ${round.games.length} results in',
                          key: ValueKey('current-pairings-round-${section.id}'),
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                if (section.rounds.lastOrNull case final round?) ...[
                  for (final game
                      in (List<Game>.of(round.games)..sort((a, b) {
                        final board = a.board.compareTo(b.board);
                        return board == 0 ? a.leg.compareTo(b.leg) : board;
                      })))
                    Padding(
                      key: ValueKey('current-pairing-${game.id}'),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Board ${game.board}'
                            '${section.doubleGames ? ' · Game ${game.leg}' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          _player(
                            context,
                            game.white,
                            'White',
                            scoreMark(game.outcome, white: true),
                          ),
                          _player(
                            context,
                            game.black,
                            'Black',
                            scoreMark(game.outcome, white: false),
                          ),
                          if (!game.outcome.resolved)
                            Text(
                              game.outcome == Outcome.disputed
                                  ? 'Disputed result'
                                  : game.outcome == Outcome.unfinished
                                  ? 'Unfinished game'
                                  : 'Awaiting result',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          const Divider(height: 12),
                        ],
                      ),
                    ),
                  for (final bye in round.byes)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(event.player(bye.player).name),
                      subtitle: Text('Bye · ${halves(bye.points)} points'),
                      onTap: () => onPlayer(bye.player),
                    ),
                ] else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No pairings yet. Create a round to see the boards here.',
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _player(BuildContext context, String id, String color, String score) =>
      InkWell(
        onTap: () => onPlayer(id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 52 * MediaQuery.textScalerOf(context).scale(14) / 14,
                child: Text(
                  color,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(child: Text(event.player(id).name)),
              const SizedBox(width: 8),
              Text(
                score.isEmpty ? '–' : score,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
}
