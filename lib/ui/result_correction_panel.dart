import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/result_correction.dart';
import 'panels.dart';
import 'result_keys.dart';
import 'side_panel.dart';
import 'theme.dart';

/// Opens the correction for [gameId] in the docked panel beside the table.
/// [outcome] preselects a result, as when it was typed into a locked score
/// box. [onDone] runs when the panel closes, after saving or not.
void openResultCorrection(
  BuildContext context,
  TournamentController controller,
  String gameId, {
  Outcome? outcome,
  VoidCallback? onSaved,
  VoidCallback? onDone,
}) {
  final dock = Dock.maybeOf(context);
  if (dock == null) return;
  void close() {
    dock.close();
    onDone?.call();
  }

  dock.show(
    'correction',
    ResultCorrectionPanel(
      key: ValueKey('correction-$gameId-${outcome?.name}'),
      controller: controller,
      gameId: gameId,
      outcome: outcome,
      onSaved: onSaved,
      onClose: close,
    ),
  );
}

/// One correction: pick the result, decide what happens to later rounds when
/// any are paired, optionally note why, and save. Closing keeps the draft.
class ResultCorrectionPanel extends StatefulWidget {
  const ResultCorrectionPanel({
    required this.controller,
    required this.gameId,
    required this.onClose,
    this.outcome,
    this.onSaved,
    super.key,
  });
  final TournamentController controller;
  final String gameId;
  final Outcome? outcome;
  final VoidCallback onClose;
  final VoidCallback? onSaved;
  @override
  State<ResultCorrectionPanel> createState() => _ResultCorrectionPanelState();
}

class _ResultCorrectionPanelState extends State<ResultCorrectionPanel> {
  TournamentController get c => widget.controller;
  String get draftKey => 'draft-correction-${widget.gameId}';
  final choices = FocusNode(debugLabel: 'correction result');
  final note = TextEditingController();
  Outcome? outcome;
  int? reopenFrom;
  bool confirmed = false, more = false;
  String? error;

  /// What was saved, so the panel can confirm it and offer Undo in place.
  ({String game, Outcome from, Outcome to, int? reopened, int head})? saved;

  // Reviews are rebuilt per revision, so an edit made beside the open panel
  // never leaves it saving against stale data.
  (int, ResultCorrection?)? _review;
  ResultCorrection? get review {
    final revision = c.event!.revision;
    if (_review?.$1 != revision) {
      ResultCorrection? next;
      try {
        next = c.reviewResult(widget.gameId);
      } on TournamentException {
        next = null;
      }
      _review = (revision, next);
    }
    return _review!.$2;
  }

  @override
  void initState() {
    super.initState();
    final draft = c.workspaceState.readMap(draftKey);
    outcome =
        widget.outcome ??
        Outcome.values.where((o) => o.name == draft['outcome']).firstOrNull;
    note.text = draft['note'] as String? ?? '';
    reopenFrom = draft['reopenFrom'] as int?;
    note.addListener(remember);
    c.addListener(changed);
    final initial = outcome ?? review?.game.outcome;
    more = initial != null && !_main.contains(initial);
  }

  @override
  void dispose() {
    c.removeListener(changed);
    choices.dispose();
    note.dispose();
    super.dispose();
  }

  void changed() {
    if (!mounted || saved != null) return;
    final r = review;
    // A round that has since started can no longer be unpaired.
    if (r != null && reopenFrom != null && !r.canReopenFrom(reopenFrom!)) {
      reopenFrom = null;
      confirmed = false;
    }
    setState(() {});
  }

  void remember() {
    if (saved != null) return;
    c.workspaceState.writeMap(draftKey, {
      'outcome': ?outcome?.name,
      'note': note.text,
      'reopenFrom': ?reopenFrom,
    });
  }

  void pick(Outcome next) {
    setState(() {
      outcome = next;
      error = null;
      if (!_main.contains(next)) more = true;
    });
    remember();
  }

  void pickReopen(int? round) {
    setState(() {
      reopenFrom = round;
      confirmed = false;
      error = null;
    });
    remember();
  }

  static const _main = [Outcome.whiteWin, Outcome.draw, Outcome.blackWin];
  static const _more = [
    Outcome.whiteForfeit,
    Outcome.blackForfeit,
    Outcome.doubleForfeit,
    Outcome.unfinished,
    Outcome.disputed,
    Outcome.unreported,
  ];

  /// Why Save is unavailable, said beside it instead of greying it silently.
  String? blocker(ResultCorrection r, Outcome chosen) {
    if (chosen == r.game.outcome) {
      return 'Choose a result different from the recorded ${r.game.outcome.label}.';
    }
    if (reopenFrom != null && !confirmed) {
      return 'Confirm that no game from round $reopenFrom on has started.';
    }
    return null;
  }

  void save() {
    final r = review;
    if (r == null) return;
    final chosen = outcome ?? r.game.outcome;
    if (blocker(r, chosen) != null) return;
    // Saving notifies listeners, which clears a reopen choice the new event
    // no longer offers; read it first.
    final reopened = reopenFrom;
    try {
      c.correctResult(
        r,
        chosen,
        reason: note.text,
        reopenFrom: reopened,
        confirmedUnstarted: confirmed,
      );
      c.workspaceState.write(draftKey, '');
      setState(() {
        saved = (
          game:
              '${r.section.name} round ${r.round.number}, board ${r.game.board}',
          from: r.game.outcome,
          to: chosen,
          reopened: reopened,
          head: c.graph.head!,
        );
        reopenFrom = null;
        error = null;
      });
      widget.onSaved?.call();
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  void undoSaved() {
    if (saved == null || c.graph.head != saved!.head) return;
    try {
      c.undo(acceptLosses: true);
      setState(() {
        outcome = saved!.to;
        reopenFrom = saved!.reopened;
        confirmed = false;
        saved = null;
      });
      remember();
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  KeyEventResult key(FocusNode _, KeyEvent event, List<Outcome> visible) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final r = review;
    if (r == null) return KeyEventResult.ignored;
    final current = outcome ?? r.game.outcome;
    final index = visible.indexOf(current);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        pick(visible[index < 0 ? 0 : (index + 1) % visible.length]);
      case LogicalKeyboardKey.arrowUp:
        pick(visible[index <= 0 ? visible.length - 1 : index - 1]);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        save();
      default:
        final next = resultFromKey(event, white: true);
        if (next == null) return KeyEventResult.ignored;
        pick(next);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final r = review;
    if (saved != null) return _savedState(context);
    if (r == null) {
      return SidePanel(
        title: 'Correct a result',
        onClose: widget.onClose,
        children: const [
          Text(
            'This game is no longer in the event. It may have been unpaired by another change.',
          ),
        ],
      );
    }
    final g = r.game, e = r.event, colors = Theme.of(context).colorScheme;
    final white = e.player(g.white).name, black = e.player(g.black).name;
    final chosen = outcome ?? g.outcome;
    final visible = [..._main, if (more) ..._more];
    final why = blocker(r, chosen);
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    String name(Outcome o) => switch (o) {
      Outcome.whiteWin => '$white won',
      Outcome.blackWin => '$black won',
      Outcome.draw => 'Draw',
      Outcome.whiteForfeit => '$white wins by forfeit',
      Outcome.blackForfeit => '$black wins by forfeit',
      Outcome.doubleForfeit => 'Double forfeit',
      Outcome.unfinished => 'Still playing',
      Outcome.disputed => 'Disputed',
      Outcome.unreported => 'No result',
    };
    String keys(Outcome o) => switch (o) {
      Outcome.whiteWin => '1',
      Outcome.blackWin => '0',
      Outcome.draw => 'D',
      Outcome.whiteForfeit => 'X',
      Outcome.blackForfeit => 'F',
      Outcome.doubleForfeit => '',
      Outcome.unfinished => 'P',
      Outcome.disputed => '?',
      Outcome.unreported => 'Del',
    };
    final later = [
      for (final round in r.later) (r.section, round, false),
      for (final (s, round) in r.relatedRounds) (s, round, true),
    ];
    final reopenable = [
      for (final round in r.later)
        if (r.canReopenFrom(round.number)) round.number,
    ];
    return KeyedSubtree(
      key: const ValueKey('result-correction-review'),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): save,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): save,
        },
        child: SidePanel(
          title: 'Correct board ${g.board}',
          onClose: widget.onClose,
          footer: [
            if (error != null)
              _Notice(
                key: const ValueKey('correction-error'),
                icon: Icons.error_outline,
                text: error!,
                color: colors.error,
              )
            else if (why != null)
              Text(why, style: muted),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('apply-correction'),
              onPressed: why == null ? save : null,
              child: Text(
                reopenFrom == null
                    ? 'Save correction'
                    : 'Save and unpair from round $reopenFrom',
              ),
            ),
          ],
          children: [
            Text(
              '${r.section.name} · Round ${r.round.number}${r.section.doubleGames ? ' · Game ${g.leg}' : ''}',
              style: muted,
            ),
            const SizedBox(height: 4),
            Text(
              '$white – $black',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('White – Black', style: muted),
            const SizedBox(height: 16),
            Focus(
              focusNode: choices,
              autofocus: true,
              onKeyEvent: (node, event) => key(node, event, visible),
              child: Builder(
                builder: (context) => _ChoiceGroup(
                  focused: Focus.of(context).hasFocus,
                  semanticLabel: 'Corrected result',
                  children: [
                    for (final o in visible)
                      _Choice(
                        key: ValueKey('correction-${o.name}'),
                        label: name(o),
                        keyHint: keys(o),
                        selected: o == chosen,
                        recorded: o == g.outcome,
                        onTap: () {
                          pick(o);
                          choices.requestFocus();
                        },
                      ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('correction-more'),
                onPressed: _more.contains(chosen)
                    ? null
                    : () => setState(() => more = !more),
                icon: Icon(more ? Icons.expand_less : Icons.expand_more),
                label: Text(more ? 'Fewer results' : 'Forfeits and more'),
              ),
            ),
            if (chosen != g.outcome) ...[
              const SizedBox(height: 8),
              _ScoreChange(
                rows: [
                  (white, g.outcome.whiteScore, chosen.whiteScore),
                  (black, g.outcome.blackScore, chosen.blackScore),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                chosen.resolved
                    ? 'Standings and tiebreaks update when you save.'
                    : 'This game will be open again. Finish it or set a pairing assumption before pairing the next round.',
                style: muted,
              ),
            ],
            if (later.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                later.length == 1
                    ? '${later.single.$3 ? '${later.single.$1.name} round' : 'Round'} ${later.single.$2.number} is already paired'
                    : 'Later rounds are already paired',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _ChoiceGroup(
                semanticLabel: 'Later rounds',
                children: [
                  _Choice(
                    key: const ValueKey('keep-pairings'),
                    label: 'Keep the pairings',
                    detail: 'Games already paired stand as they are.',
                    selected: reopenFrom == null,
                    onTap: () => pickReopen(null),
                  ),
                  for (final n in reopenable)
                    _Choice(
                      key: ValueKey('reopen-round-$n'),
                      label: 'Unpair from round $n',
                      detail: n == r.later.last.number
                          ? 'Removes round $n so it can be paired again.'
                          : 'Removes round $n and every round after it so they can be paired again.',
                      selected: reopenFrom == n,
                      onTap: () => pickReopen(n),
                    ),
                ],
              ),
              for (final (s, round, related) in later)
                if (related || !reopenable.contains(round.number))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      related || r.hasTransfers
                          ? '${s.name} round ${round.number} is linked by a section transfer and stays paired. Fix its pairings separately if needed.'
                          : 'Round ${round.number} has recorded play, so it stays paired.',
                      style: muted,
                    ),
                  ),
              if (reopenFrom != null) ...[
                const SizedBox(height: 12),
                _Confirm(
                  key: const ValueKey('confirm-unstarted'),
                  value: confirmed,
                  label:
                      'No game from round $reopenFrom on has started at the boards.',
                  onChanged: (v) => setState(() => confirmed = v),
                ),
                const SizedBox(height: 4),
                Text(
                  'After saving, pair round $reopenFrom again with Create pairings.',
                  style: muted,
                ),
              ],
            ],
            const SizedBox(height: 24),
            TextField(
              key: const ValueKey('result-reason'),
              controller: note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              minLines: 1,
              maxLines: 3,
              onSubmitted: (_) => save(),
            ),
            const SizedBox(height: 8),
            Text('The earlier version stays in History.', style: muted),
          ],
        ),
      ),
    );
  }

  Widget _savedState(BuildContext context) {
    final s = saved!;
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    final canUndo = c.graph.head == s.head;
    return KeyedSubtree(
      key: const ValueKey('correction-saved'),
      child: SidePanel(
        title: 'Result corrected',
        onClose: widget.onClose,
        footer: [
          Row(
            children: [
              if (canUndo)
                OutlinedButton.icon(
                  key: const ValueKey('correction-undo'),
                  onPressed: undoSaved,
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo'),
                ),
              const Spacer(),
              OutlinedButton(
                key: const ValueKey('correction-done'),
                autofocus: true,
                onPressed: widget.onClose,
                child: const Text('Done'),
              ),
            ],
          ),
        ],
        children: [
          _Notice(
            icon: Icons.check_circle_outline,
            text: '${s.game} is now ${s.to.label} (was ${s.from.label}).',
            color: colors.onSurface,
          ),
          const SizedBox(height: 12),
          Text('Standings and tiebreaks are up to date.', style: muted),
          if (s.reopened != null) ...[
            const SizedBox(height: 8),
            Text(
              'Round ${s.reopened} onward is unpaired. Pair it again with Create pairings.',
              style: muted,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Reprint anything already posted for this section, such as wall sheets and standings.',
            style: muted,
          ),
        ],
      ),
    );
  }
}

/// A ruled list of mutually exclusive choices, focused as one control.
class _ChoiceGroup extends StatelessWidget {
  const _ChoiceGroup({
    required this.children,
    required this.semanticLabel,
    this.focused = false,
  });
  final List<Widget> children;
  final String semanticLabel;
  final bool focused;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      container: true,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: focused ? focusRing(colors) : colors.outline,
            width: focused ? focusRingWidth : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        // Rows clip to the group's corners so a selected row stays square.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, color: colors.outlineVariant),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
    this.keyHint,
    this.recorded = false,
    super.key,
  });
  final String label;
  final String? detail, keyHint;
  final bool selected, recorded;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: [label, if (recorded) 'recorded', ?detail].join(', '),
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.surfaceContainerHigh : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          canRequestFocus: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: controlHeight + 4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? colors.onSurface : colors.outline,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        if (detail != null)
                          Text(
                            detail!,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (recorded) ...[
                    const SizedBox(width: 8),
                    const StatusPill('Recorded'),
                  ],
                  if (keyHint != null)
                    SizedBox(
                      width: 32,
                      child: Text(
                        keyHint!,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontFamily: 'SourceCodePro',
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Each player's points before and after, in tabular figures.
class _ScoreChange extends StatelessWidget {
  const _ScoreChange({required this.rows});
  final List<(String, int, int)> rows;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const figures = [FontFeature.tabularFigures()];
    return Container(
      key: const ValueKey('correction-score-change'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          for (final (name, before, after) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${scoreText(before)} → ',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontFeatures: figures,
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      scoreText(after),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: before == after
                            ? FontWeight.w400
                            : FontWeight.w600,
                        fontFeatures: figures,
                      ),
                    ),
                  ),
                  Text(' pt', style: TextStyle(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Confirm extends StatelessWidget {
  const _Confirm({
    required this.value,
    required this.label,
    required this.onChanged,
    super.key,
  });
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    canRequestFocus: false,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlainCheckbox(
          value: value,
          label: label,
          onChanged: (v) => onChanged(v ?? false),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(label),
          ),
        ),
      ],
    ),
  );
}

/// An icon and words, so state never rests on colour alone.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    required this.color,
    super.key,
  });
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: TextStyle(color: color)),
      ),
    ],
  );
}
