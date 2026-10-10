import 'package:flutter/material.dart';

import '../../application/tournament_controller.dart';
import '../../domain/knockout.dart';
import '../../domain/model.dart';
import '../dialogs.dart' show showFailure;
import '../select.dart';

/// A knockout section's standings: the bracket as a ruled table, one row
/// per match per stage, with the placings underneath. A drawn match in a
/// section with no tie-break games offers an inline "Advance…" choice that
/// applies at once (undo is in the toolbar).
class KnockoutBracketView extends StatefulWidget {
  const KnockoutBracketView({
    required this.controller,
    required this.section,
    super.key,
  });
  final TournamentController controller;
  final Section section;

  @override
  State<KnockoutBracketView> createState() => _KnockoutBracketViewState();
}

class _KnockoutBracketViewState extends State<KnockoutBracketView> {
  /// The reason typed for each drawn board, kept until it is applied.
  final reasons = <int, TextEditingController>{};

  @override
  void dispose() {
    for (final c in reasons.values) {
      c.dispose();
    }
    super.dispose();
  }

  void advance(int board, String playerId) {
    try {
      widget.controller.advanceKnockout(
        widget.section.id,
        board,
        playerId,
        reason: reasons[board]?.text ?? '',
      );
    } catch (error) {
      showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.controller.event!;
    final s = widget.section;
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant);
    final rule = BorderSide(
      color: colors.outlineVariant.withValues(alpha: 0.5),
    );
    if (s.players.length < 2) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('A knockout needs at least two players.', style: muted),
      );
    }
    final bracket = knockoutBracket(e, s);
    String name(String? id) => id == null ? '—' : e.player(id).name;
    String seeded(String? id, int seed) =>
        id == null ? '—' : '#$seed ${name(id)}';
    final directorDecides = bracket.tiebreak == 'none';

    Widget cell(double width, Widget child) => SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: child,
      ),
    );
    Widget text(double width, String value, [TextStyle? style]) => cell(
      width,
      Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: style),
    );

    Widget outcome(KnockoutMatch m) {
      switch (m.status) {
        case KnockoutMatchStatus.bye:
          return Text(
            '${name(m.advanced)} advances without a game',
            style: muted,
          );
        case KnockoutMatchStatus.waiting:
          return Text('Waiting for the previous round', style: muted);
        case KnockoutMatchStatus.unpaired:
          return Text('Not yet paired', style: muted);
        case KnockoutMatchStatus.pending:
          return Text('In progress', style: muted);
        case KnockoutMatchStatus.decided:
          return Text(
            '${name(m.advanced)} advances'
            '${m.reason.isEmpty ? '' : ' · ${m.reason}'}',
          );
        case KnockoutMatchStatus.tied:
          if (!directorDecides) {
            return Text('Drawn match · tie-break games next', style: muted);
          }
          final reason = reasons.putIfAbsent(
            m.board,
            TextEditingController.new,
          );
          return Row(
            children: [
              Expanded(
                child: PlainSelect<String>(
                  key: ValueKey('advance-${m.board}'),
                  value: '',
                  hint: 'Advance…',
                  dense: true,
                  options: [
                    SelectOption(m.high!, name(m.high)),
                    SelectOption(m.low!, name(m.low)),
                  ],
                  onChanged: (id) => advance(m.board, id),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: ValueKey('advance-reason-${m.board}'),
                  controller: reason,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Reason (coin toss, higher seed…)',
                  ),
                ),
              ),
            ],
          );
      }
    }

    Widget row(
      List<Widget> cells, {
      bool header = false,
      bool bordered = true,
    }) => Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: bordered ? rule : BorderSide.none),
      ),
      child: Row(children: cells),
    );
    final headerStyle = TextStyle(
      fontWeight: FontWeight.w600,
      color: colors.onSurfaceVariant,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row([
              text(120, 'Stage', headerStyle),
              text(60, 'Board', headerStyle),
              text(260, 'Match', headerStyle),
              text(150, 'Games', headerStyle),
              Expanded(child: Text('Advances', style: headerStyle)),
            ]),
            for (final stage in bracket.stages)
              for (final m in stage.matches)
                KeyedSubtree(
                  key: ValueKey('match-${stage.number}-${m.index}'),
                  child: row([
                    text(120, m.index == 0 ? stage.name : ''),
                    text(60, m.board == 0 ? '' : '${m.board}', muted),
                    text(
                      260,
                      '${seeded(m.high, m.highSeed)} – ${seeded(m.low, m.lowSeed)}',
                    ),
                    text(150, knockoutMatchScore(m)),
                    Expanded(child: outcome(m)),
                  ]),
                ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Text(
                key: const ValueKey('knockout-placings'),
                'Placings: ${knockoutPlacings(e, s).map((p) => '${name(p.$1)} – ${p.$2}').join('; ')}',
                style: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
