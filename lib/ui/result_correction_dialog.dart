import 'package:flutter/services.dart';
import 'result_keys.dart';
import 'package:flutter/material.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/result_correction.dart';

Future<bool> reviewResultCorrection(
  BuildContext context,
  TournamentController controller,
  String gameId, {
  Outcome? outcome,
  String reason = '',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _CorrectionDialog(
        controller: controller,
        review: controller.reviewResult(gameId),
        outcome: outcome,
        reason: reason,
      ),
    ) ??
    false;

class _CorrectionDialog extends StatefulWidget {
  const _CorrectionDialog({
    required this.controller,
    required this.review,
    this.outcome,
    required this.reason,
  });
  final TournamentController controller;
  final ResultCorrection review;
  final Outcome? outcome;
  final String reason;
  @override
  State<_CorrectionDialog> createState() => _CorrectionDialogState();
}

class _CorrectionDialogState extends State<_CorrectionDialog> {
  late Outcome outcome = widget.outcome ?? widget.review.game.outcome;
  late final reason = TextEditingController(text: widget.reason);
  int? reopenFrom;
  bool confirmed = false;
  String? error;
  ResultCorrection get review => widget.review;

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  void save() {
    try {
      widget.controller.correctResult(
        review,
        outcome,
        reason: reason.text,
        reopenFrom: reopenFrom,
        confirmedUnstarted: confirmed,
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  Widget step(IconData icon, String title, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ],
    ),
  );

  Widget laterRound(Section section, Round round, {bool related = false}) {
    final reopen =
        !related && reopenFrom != null && round.number >= reopenFrom!;
    final results = round.games
        .where((g) => g.outcome != Outcome.unreported)
        .length;
    final canReopen = !related && review.canReopenFrom(round.number);
    final status = reopen
        ? 'Reopen for new pairings'
        : 'Keep pairings and results';
    return Container(
      key: ValueKey('impact-${section.id}-${round.number}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(
          color: reopen
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: reopen ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${related ? '${section.name} · ' : ''}Round ${round.number} · ${round.games.length} boards',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '$status${round.hasPlay ? ' · ${round.startedAt != null ? 'started' : 'play recorded'}, $results results' : ''}',
          ),
          if (!canReopen && !reopen)
            Text(
              related || review.hasTransfers
                  ? 'Linked by a section transfer; repair pairings separately.'
                  : 'Recorded play in this or a later round prevents reopening.',
            ),
          if (canReopen)
            TextButton(
              key: ValueKey('reopen-round-${round.number}'),
              onPressed: () => setState(() {
                reopenFrom = reopenFrom == round.number ? null : round.number;
                confirmed = false;
              }),
              child: Text(
                reopenFrom == round.number
                    ? 'Keep these pairings instead'
                    : 'Reopen from round ${round.number}',
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = review.game, e = review.event;
    final canSave =
        outcome != g.outcome &&
        reason.text.trim().isNotEmpty &&
        (reopenFrom == null || confirmed);
    return AlertDialog(
      key: const ValueKey('result-correction-review'),
      title: const Text('Review result correction'),
      scrollable: true,
      content: SizedBox(
        width: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${review.section.name} · Round ${review.round.number} · Board ${g.board}${review.section.doubleGames ? ' · Game ${g.leg}' : ''}',
            ),
            const SizedBox(height: 20),
            step(
              Icons.edit_outlined,
              '1. Correct the result',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${e.player(g.white).name} (White) — ${e.player(g.black).name} (Black)',
                  ),
                  const SizedBox(height: 8),
                  Text('Recorded: ${g.outcome.label}'),
                  const SizedBox(height: 12),
                  Focus(
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent ||
                          HardwareKeyboard.instance.isControlPressed ||
                          HardwareKeyboard.instance.isMetaPressed ||
                          HardwareKeyboard.instance.isAltPressed) {
                        return KeyEventResult.ignored;
                      }
                      final next = resultFromKey(event, white: true);
                      if (next == null) return KeyEventResult.ignored;
                      setState(() => outcome = next);
                      return KeyEventResult.handled;
                    },
                    child: Builder(
                      builder: (context) => GestureDetector(
                        key: const ValueKey('correction-outcome'),
                        onTap: () => Focus.of(context).requestFocus(),
                        child: InputDecorator(
                          isFocused: Focus.of(context).hasFocus,
                          decoration: const InputDecoration(
                            labelText: 'White’s corrected result',
                            helperText: resultKeyHint,
                          ),
                          child: Text(outcome.label),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${e.player(g.white).name}: ${scoreText(g.outcome.whiteScore)} → ${scoreText(outcome.whiteScore)} pt\n'
                    '${e.player(g.black).name}: ${scoreText(g.outcome.blackScore)} → ${scoreText(outcome.blackScore)} pt',
                  ),
                  if (!outcome.resolved)
                    const Text(
                      'This game will be unresolved. Complete it or set a pairing assumption before pairing again.',
                    ),
                ],
              ),
            ),
            step(
              Icons.account_tree_outlined,
              '2. Decide what happens next',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Standings and tiebreaks recalculate from the corrected result.',
                  ),
                  const SizedBox(height: 8),
                  if (!review.hasDependencies)
                    const Text('No later pairings depend on this result.'),
                  if (review.later.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Keep games that will stand as played or posted. Reopening a round also reopens every round after it.',
                      ),
                    ),
                  for (final r in review.later) laterRound(review.section, r),
                  for (final (s, r) in review.relatedRounds)
                    laterRound(s, r, related: true),
                  if (review.hasTransfers)
                    const Text(
                      'A later section transfer carries these scores forward. Player placements stay as they are; automatic reopening is unavailable.',
                    ),
                  if (reopenFrom != null) ...[
                    Text(
                      'Round $reopenFrom onward will leave the live schedule. Use Post round $reopenFrom to generate and review replacement pairings.',
                    ),
                    CheckboxListTile(
                      key: const ValueKey('confirm-unstarted'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'I checked that none of these games have actually started.',
                      ),
                      value: confirmed,
                      onChanged: (v) => setState(() => confirmed = v!),
                    ),
                  ],
                ],
              ),
            ),
            step(
              Icons.receipt_long_outlined,
              '3. Save one correction',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'The previous version stays in History. Replace affected printed standings, pairings and reports; existing copies do not update themselves.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('result-reason'),
                    controller: reason,
                    decoration: const InputDecoration(
                      labelText: 'Reason for correction',
                      hintText: 'For example: checked the signed scoresheet',
                    ),
                    minLines: 1,
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('apply-correction'),
          onPressed: canSave ? save : null,
          child: Text(
            reopenFrom == null ? 'Save correction' : 'Save and reopen',
          ),
        ),
      ],
    );
  }
}
