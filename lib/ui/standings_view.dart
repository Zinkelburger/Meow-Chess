import 'package:flutter/material.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/standings.dart';
import '../infrastructure/reports.dart';
import 'players_view.dart';
import 'theme.dart';

class StandingsView extends StatefulWidget {
  const StandingsView({required this.controller, this.sectionId, super.key});
  final TournamentController controller;
  final String? sectionId;
  @override
  State<StandingsView> createState() => _StandingsViewState();
}

class _StandingsViewState extends State<StandingsView> {
  bool wallchart = false;
  int ceiling = 0;
  @override
  Widget build(BuildContext context) {
    final e = widget.controller.event!;
    final sections = e.sections
        .where(
          (s) =>
              s.players.isNotEmpty &&
              (widget.sectionId == null || s.id == widget.sectionId),
        )
        .toList();
    if (sections.isEmpty) {
      return const EmptyState(
        icon: Icons.leaderboard_outlined,
        title: 'A place for every result',
        body: 'Create sections to see standings and the crosstable.',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Standings')),
                  ButtonSegment(value: true, label: Text('Crosstable')),
                ],
                selected: {wallchart},
                onSelectionChanged: (s) => setState(() => wallchart = s.first),
              ),
              DropdownButton<int>(
                value: ceiling,
                items: [
                  for (final n in [
                    0,
                    2200,
                    2000,
                    1900,
                    1800,
                    1600,
                    1500,
                    1400,
                    1200,
                  ])
                    DropdownMenuItem(
                      value: n,
                      child: Text(n == 0 ? 'All prize classes' : 'Under $n'),
                    ),
                ],
                onChanged: (v) => setState(() => ceiling = v!),
              ),
            ],
          ),
        ),
        Expanded(
          child: wallchart
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SelectableText(
                        crosstable(e.copy(sections: sections)),
                        style: const TextStyle(
                          fontFamily: 'SourceCodePro',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    for (final s in sections) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          s.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Rank')),
                            DataColumn(label: Text('Player')),
                            DataColumn(label: Text('Rating'), numeric: true),
                            DataColumn(label: Text('Points'), numeric: true),
                            DataColumn(label: Text('Buchholz'), numeric: true),
                            DataColumn(label: Text('SB'), numeric: true),
                            DataColumn(label: Text('Played'), numeric: true),
                          ],
                          rows: [
                            for (final (_, row)
                                in standings(e, s)
                                    .where(
                                      (r) =>
                                          ceiling == 0 ||
                                          (r.player.rating > 0 &&
                                              r.player.rating < ceiling),
                                    )
                                    .indexed)
                              DataRow(
                                cells: [
                                  DataCell(Text('${row.rank}')),
                                  DataCell(
                                    Text(row.player.name),
                                    onTap: () => editPlayer(
                                      context,
                                      widget.controller,
                                      player: row.player,
                                    ),
                                  ),
                                  DataCell(Text('${row.player.rating}')),
                                  DataCell(
                                    Text(
                                      scoreText(row.points),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(scoreText(row.buchholz))),
                                  DataCell(Text('${row.sonneborn / 4}')),
                                  DataCell(Text('${row.played}')),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Points → played-opponent Buchholz → Sonneborn–Berger. Equal values are tied; alphabetical order is for display. Prize-class filters exclude unrated entries. This pilot uses the displayed tie-break policy.',
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
