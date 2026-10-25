import 'package:flutter/material.dart';

import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/prizes.dart';
import '../domain/team_standings.dart';
import '../infrastructure/reports.dart' show ReportKind, reportName;
import 'membership_style.dart' show attentionColor;
import 'panels.dart' show Dock, showPrint;
import 'prize_panel.dart';
import 'theme.dart';

/// Where [section] stands for its awards, in words: still to play, still
/// playing, or final. [done] is true once every planned round has every
/// result, so the awards can be handed out.
({String text, bool done}) awardsProgress(Section section) {
  if (section.rounds.isEmpty) {
    return (text: 'Not started', done: false);
  }
  final last = section.rounds.last;
  final open = last.games.where((g) => !g.outcome.resolved).length;
  if (open > 0) {
    return (
      text:
          'Provisional · round ${last.number}: $open '
          '${open == 1 ? 'game' : 'games'} still playing',
      done: false,
    );
  }
  if (!section.finished) {
    return (
      text:
          'Provisional · after round ${last.number} of ${section.plannedRounds}',
      done: false,
    );
  }
  return (text: 'Final', done: true);
}

/// One award as the announcer reads it: the prize, who takes it, what it
/// is, and the score that won it.
class AwardRow {
  const AwardRow({
    required this.key,
    required this.prize,
    required this.award,
    required this.winner,
    this.points,
    this.detail = '',
    this.lot = false,
  });

  /// Stable while the winner is: the handed-out tick belongs to it.
  final String key;
  final String prize, award;

  /// Who receives it; empty when nobody does.
  final String winner;
  final int? points;

  /// The tie-break that decided it, how a tie shared the cash, or why
  /// nobody takes it.
  final String detail;

  /// The tie-breaks did not separate the tied players (34A): the director
  /// decides by lot.
  final bool lot;
}

/// [section]'s awards in announced order: team prizes, then individual.
List<AwardRow> awardRows(Event event, Section section) {
  String name(String id) =>
      event.players.where((p) => p.id == id).firstOrNull?.name ?? id;
  final rows = <AwardRow>[];
  final teams = allocateTeamPrizes(event, section);
  for (final l in teams.lines) {
    final winner =
        l.trophyTeam ?? (l.cash.length == 1 ? l.cash.keys.single : null);
    rows.add(
      AwardRow(
        key: '${section.id}|${l.prize.id}|team:${winner ?? ''}',
        prize: l.prize.title,
        award: _award(l.prize, l.paidCents),
        winner:
            winner ??
            (l.cash.isEmpty ? '' : 'Shared: ${l.cash.keys.join(', ')}'),
        detail: l.cash.length > 1
            ? l.cash.entries
                  .map((c) => '${c.key} ${dollars(c.value)}')
                  .join(', ')
            : l.note,
      ),
    );
  }
  final a = allocatePrizes(event, section);
  final points = {for (final w in a.awards) w.player.id: w.points};
  for (final l in a.lines) {
    final cash = l.cash.entries.toList();
    final winner =
        l.trophyWinner ??
        (cash.length == 1 && l.pooledWith.isEmpty ? cash.single.key : null);
    final shared = winner == null && cash.isNotEmpty;
    rows.add(
      AwardRow(
        key: '${section.id}|${l.prize.id}|${winner ?? ''}',
        prize: l.prize.title,
        award: _award(l.prize, l.paidCents),
        winner: winner != null
            ? reportName(name(winner))
            : shared
            ? 'Shared: ${cash.map((c) => reportName(name(c.key))).join(', ')}'
            : '',
        points: winner != null
            ? points[winner]
            : shared
            ? points[cash.first.key]
            : null,
        detail: [
          if (l.trophyNote.isNotEmpty) l.trophyNote,
          // The cash of a trophy prize can go to a tie the trophy did not.
          if (cash.length > 1 || (cash.isNotEmpty && winner != cash.first.key))
            cash.map((c) => '${name(c.key)} ${dollars(c.value)}').join(', '),
          if (winner == null && !shared && l.note.isNotEmpty) l.note,
        ].join(' · '),
        lot: l.trophyNote.contains('decide by lot'),
      ),
    );
  }
  return rows;
}

String _award(Prize p, int paidCents) => [
  if (p.award.isNotEmpty) p.award,
  if (p.cents > 0) dollars(paidCents),
].join(' + ');

/// The end of the day on one page: every section's awards in announced
/// order, who takes each one, and a tick as each is handed out. Lives at
/// the top of Reports once play has started.
class AwardsBoard extends StatefulWidget {
  const AwardsBoard({required this.controller, super.key});
  final TournamentController controller;
  @override
  State<AwardsBoard> createState() => _AwardsBoardState();
}

class _AwardsBoardState extends State<AwardsBoard> {
  static const _handed = 'awards-handed-out';
  TournamentController get c => widget.controller;

  Map<String, dynamic> get handed => c.workspaceState.readMap(_handed);

  void tick(String key, bool on) => setState(() {
    final next = Map<String, dynamic>.of(handed)..remove(key);
    if (on) next[key] = true;
    c.workspaceState.writeMap(_handed, next);
  });

  void editPrizes(Section s) {
    final dock = Dock.maybeOf(context);
    dock?.show(
      'prizes-${s.id}',
      PrizeTablePanel(
        key: ValueKey('prizes-${s.id}'),
        controller: c,
        sectionId: s.id,
        onClose: dock.close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = c.event!, theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant);
    final sections = [
      for (final s in e.sections)
        if (s.players.isNotEmpty && !s.sideGames) s,
    ];
    final prized = [
      for (final s in sections)
        if (PrizeTable.fromJson(s.prizes).list.isNotEmpty) s,
    ];
    final allDone =
        prized.isNotEmpty && prized.every((s) => awardsProgress(s).done);
    return Column(
      key: const ValueKey('awards'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Awards', style: theme.textTheme.titleLarge),
            if (prized.isNotEmpty)
              OutlinedButton.icon(
                key: const ValueKey('print-prizes'),
                onPressed: () => showPrint(context, e, kind: ReportKind.prizes),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print awards sheet'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          prized.isEmpty
              ? 'No prizes yet. Add each section’s prizes as announced; '
                    'winners appear here as results come in.'
              : allDone
              ? 'Final. Ties for a trophy or medal are decided by tie-breaks.'
              : 'Results are still coming in, so winners can change. '
                    'Ties for a trophy or medal are decided by tie-breaks.',
          key: const ValueKey('awards-state'),
          style: muted,
        ),
        for (final s in sections) ...[
          const SizedBox(height: 20),
          _section(context, s),
        ],
      ],
    );
  }

  Widget _section(BuildContext context, Section s) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    final e = c.event!;
    final rows = PrizeTable.fromJson(s.prizes).list.isEmpty
        ? const <AwardRow>[]
        : awardRows(e, s);
    final progress = awardsProgress(s);
    final heading = Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          s.name,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        Text(
          rows.isEmpty ? 'No prizes yet' : progress.text,
          key: ValueKey('awards-progress-${s.id}'),
          style: muted.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        TextButton(
          key: ValueKey('edit-prizes-${s.id}'),
          onPressed: Dock.maybeOf(context) == null ? null : () => editPrizes(s),
          child: Text(rows.isEmpty ? 'Add prizes…' : 'Prizes…'),
        ),
      ],
    );
    if (rows.isEmpty) return heading;
    final ticks = handed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        const SizedBox(height: 4),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, r) in rows.indexed)
                _row(
                  context,
                  s,
                  r,
                  first: i == 0,
                  ticked: ticks[r.key] == true,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    Section s,
    AwardRow r, {
    required bool first,
    required bool ticked,
  }) {
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final tabular = const [FontFeature.tabularFigures()];
    final attention = attentionColor(colors);
    final nobody = r.winner.isEmpty;
    final muted = TextStyle(color: colors.onSurfaceVariant);
    final prize = Text(
      r.prize,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        fontFeatures: tabular,
      ),
    );
    final award = Text(r.award, style: muted);
    final winner = Text(
      nobody
          ? s.rounds.isEmpty
                ? 'After the last round'
                : r.detail.isNotEmpty
                ? r.detail
                : 'Nobody eligible yet'
          : r.winner,
      style: nobody
          ? muted
          : TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              decoration: ticked ? TextDecoration.lineThrough : null,
              decorationColor: colors.onSurfaceVariant,
            ),
    );
    final detail = nobody || r.detail.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.lot) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.error_outline,
                      size: 16,
                      color: attention,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    r.detail,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: r.lot ? FontWeight.w600 : null,
                      color: r.lot ? attention : colors.onSurfaceVariant,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
              ],
            ),
          );
    final points = Text.rich(
      TextSpan(
        children: [
          if (r.points != null) ...[
            TextSpan(
              text: scoreText(r.points!),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFeatures: tabular,
              ),
            ),
            TextSpan(text: ' pts', style: muted.copyWith(fontSize: 12)),
          ],
        ],
      ),
      textAlign: TextAlign.right,
    );
    final check = PlainCheckbox(
      key: ValueKey('handed-${r.key}'),
      label: 'Handed out: ${r.prize} to ${r.winner}',
      value: ticked,
      onChanged: (v) => tick(r.key, v == true),
    );
    return Container(
      key: ValueKey('award-${r.key}'),
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: ticked ? colors.surfaceContainerLow : null,
        border: first
            ? null
            : Border(
                top: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // Beside an open side panel the columns stack: the prize and its
          // award above the winner, the tick without its words.
          if (box.maxWidth < 600 * scale) {
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [prize, award],
                      ),
                      winner,
                      ?detail,
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                points,
                if (!nobody) ...[const SizedBox(width: 12), check],
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 96 * scale, child: prize),
              SizedBox(width: 120 * scale, child: award),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [winner, ?detail],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(width: 64 * scale, child: points),
              const SizedBox(width: 16),
              SizedBox(
                width: 120 * scale,
                child: nobody
                    ? null
                    : Row(
                        children: [
                          check,
                          const SizedBox(width: 6),
                          Flexible(
                            child: ExcludeSemantics(
                              child: GestureDetector(
                                onTap: () => tick(r.key, !ticked),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: Text(
                                    'Handed out',
                                    style: muted.copyWith(fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
