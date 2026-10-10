import 'package:flutter/material.dart';

import '../domain/model.dart';
import '../domain/team_standings.dart';

/// The Teams table under a section's individual standings when it has
/// scholastic team awards (Scholastic Regulations 10.2, 12.3.3; rule
/// 31A1): place, team, the players whose scores count, the team score and
/// the team tie-break totals. Ruled rows on the crosstable's sheet; the
/// players wrap under the team name so the table reads at 200% text.
class TeamStandingsTable extends StatelessWidget {
  const TeamStandingsTable({
    required this.event,
    required this.section,
    super.key,
  });
  final Event event;
  final Section section;

  @override
  Widget build(BuildContext context) {
    final awards = TeamAwards.tryOf(section);
    if (awards == null) return const SizedBox.shrink();
    final rows = teamStandings(event, section, awards: awards);
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final tabular = const TextStyle(
      fontFeatures: [FontFeature.tabularFigures()],
    );
    Widget cell(double width, Widget child, {bool center = true}) => SizedBox(
      width: width * scale,
      child: center ? Center(child: child) : child,
    );
    final ruled = BoxDecoration(
      border: Border(
        bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
    );
    return Column(
      key: ValueKey('team-standings-${section.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colors.outlineVariant),
              bottom: BorderSide(color: colors.outlineVariant),
            ),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Teams',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: '   ${awards.summary}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
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
                cell(44, const Text('Rank'), center: false),
                const Expanded(child: Text('Team and scores that count')),
                cell(
                  56,
                  Text(awards.method == TeamScoring.topN ? 'Pts' : 'Rollins'),
                ),
                for (final m in teamTiebreakMethods)
                  Tooltip(
                    message: '${m.label} total',
                    child: cell(56, Text(m.short)),
                  ),
              ],
            ),
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'No player has a team label.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
        for (final t in rows)
          Container(
            key: ValueKey('team-row-${t.team}'),
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: ruled,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cell(
                  44,
                  Text(
                    !t.eligible
                        ? '—'
                        : rows.where((o) => o.rank == t.rank).length > 1
                        ? 'T-${t.rank}'
                        : '${t.rank}',
                    style: tabular.copyWith(fontWeight: FontWeight.w600),
                  ),
                  center: false,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.team,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        [
                          for (final m in t.counting)
                            '${m.player.name} ${formatTeamPoints(t.method, m.points)}',
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (!t.eligible)
                        Text(
                          'Needs ${awards.minPlayers} players for a team prize (10.2.2)',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                cell(
                  56,
                  Text(
                    t.scoreText,
                    style: tabular.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                for (final v in t.tiebreaks.take(teamTiebreakMethods.length))
                  cell(56, Text(v.text, style: tabular)),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Text(
            'Team ties: ${teamTiebreakLabels.join(', ')} (Scholastic Regulations 12.3.3).',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
