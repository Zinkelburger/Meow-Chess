import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import 'dialogs.dart';
import 'players_view.dart' show boardRange, halves;
import 'theme.dart';

class BoardRow {
  const BoardRow(this.section, this.round, this.game);
  final Section section;
  final Round round;
  final Game game;
}

/// What one player's score box shows for a game: 1, 0, ½, 1F, 0F, or blank.
String scoreMark(Outcome o, {required bool white}) => switch (o) {
  Outcome.unreported => '',
  Outcome.draw => '½',
  Outcome.unfinished => '…',
  Outcome.disputed => '?',
  Outcome.doubleForfeit => '0F',
  _ =>
    '${(white ? o.whiteScore : o.blackScore) == 2 ? 1 : 0}${o.played ? '' : 'F'}',
};

/// Rounds page: one row per board, a score box either side like a paper
/// pairing sheet. Typing 1, 0 or 5 in one player's box fills in the other.
class ResultsView extends StatefulWidget {
  const ResultsView({required this.controller, this.sectionId, super.key});
  final TournamentController controller;
  final String? sectionId;
  @override
  State<ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends State<ResultsView> {
  final scroll = ScrollController();
  final jump = TextEditingController();
  final reason = TextEditingController();

  /// Score boxes by '$gameId-w' / '$gameId-b'.
  final boxes = <String, FocusNode>{};
  final menus = <String, MenuController>{};
  bool missingOnly = false, forfeit = false, busy = false;
  int? selectedRound;
  String roundSignature = '';

  /// A result waiting for a reason, because later rounds are paired:
  /// (game, outcome, typed in White's box).
  (String, Outcome, bool)? pending;
  String get preference => 'results-${widget.sectionId ?? 'all'}';

  @override
  void initState() {
    super.initState();
    roundSignature = signature();
    final saved = widget.controller.repository.readPreference(preference);
    if (saved != null) {
      try {
        final j = jsonDecode(saved);
        missingOnly = j['missingOnly'] ?? false;
        selectedRound = j['round'];
      } catch (_) {}
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => focusFirst());
  }

  String signature() => widget.controller.event!.sections
      .where((s) => widget.sectionId == null || s.id == widget.sectionId)
      .map((s) => '${s.id}:${s.rounds.length}')
      .join('|');

  @override
  void didUpdateWidget(covariant ResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = signature();
    if (roundSignature.isNotEmpty &&
        next != roundSignature &&
        selectedRound == null) {
      forfeit = false;
      pending = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (scroll.hasClients) scroll.jumpTo(0);
        focusFirst();
      });
    }
    roundSignature = next;
  }

  @override
  void dispose() {
    for (final n in boxes.values) {
      n.dispose();
    }
    scroll.dispose();
    jump.dispose();
    reason.dispose();
    super.dispose();
  }

  FocusNode box(String gameId, bool white) => boxes.putIfAbsent(
    '$gameId-${white ? 'w' : 'b'}',
    () => FocusNode(debugLabel: 'score $gameId ${white ? 'white' : 'black'}'),
  );

  /// The board whose score box has focus, and which side.
  (BoardRow, bool)? get focused {
    for (final r in rows()) {
      if (boxes['${r.game.id}-w']?.hasFocus ?? false) return (r, true);
      if (boxes['${r.game.id}-b']?.hasFocus ?? false) return (r, false);
    }
    return null;
  }

  List<BoardRow> rows() {
    final result = <BoardRow>[];
    for (final s in widget.controller.event!.sections.where(
      (s) => widget.sectionId == null || s.id == widget.sectionId,
    )) {
      final r = selectedRound == null
          ? s.rounds.lastOrNull
          : s.rounds.where((r) => r.number == selectedRound).firstOrNull;
      if (r != null) {
        for (final g in r.games) {
          result.add(BoardRow(s, r, g));
        }
      }
    }
    result.sort((a, b) {
      final board = a.game.board.compareTo(b.game.board);
      return board != 0 ? board : a.game.leg.compareTo(b.game.leg);
    });
    return result;
  }

  List<BoardRow> visibleRows() =>
      rows().where((r) => !missingOnly || !r.game.outcome.resolved).toList();

  void remember() {
    try {
      widget.controller.repository.writePreference(
        preference,
        jsonEncode({'missingOnly': missingOnly, 'round': selectedRound}),
      );
    } catch (e) {
      showFailure(context, e);
    }
  }

  void focusBox(String gameId, bool white) {
    final node = box(gameId, white)..requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = node.context;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(
          target,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
        Scrollable.ensureVisible(
          target,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
    });
  }

  /// Puts the cursor in White's box on the first board without a result.
  void focusFirst() {
    if (!mounted) return;
    final all = visibleRows();
    final row =
        all.where((r) => !r.game.outcome.resolved).firstOrNull ??
        all.firstOrNull;
    if (row != null) focusBox(row.game.id, true);
  }

  /// Moves [by] boards up or down, keeping the same side.
  void step(String gameId, bool white, int by) {
    final all = visibleRows();
    if (all.isEmpty) return;
    final i = all.indexWhere((r) => r.game.id == gameId);
    final next = all[(i + by).clamp(0, all.length - 1)];
    focusBox(next.game.id, white);
  }

  /// After a result: the next board still missing one, same side.
  void advance(String gameId, bool white) {
    final all = rows();
    final i = all.indexWhere((r) => r.game.id == gameId);
    final next = all
        .skip(i + 1)
        .where((r) => !r.game.outcome.resolved)
        .firstOrNull;
    if (next != null) {
      focusBox(next.game.id, white);
    } else if (!missingOnly) {
      focusBox(gameId, white);
    }
  }

  /// Records [outcome]. If later rounds are paired a reason is asked for
  /// inline first.
  void enter(BoardRow row, Outcome outcome, {required bool white}) {
    if (busy) return;
    if (row.game.outcome == outcome) {
      advance(row.game.id, white);
      return;
    }
    if (widget.controller.correctionHasDependencies(row.game.id)) {
      setState(() => pending = (row.game.id, outcome, white));
      return;
    }
    save(row, outcome, white: white);
  }

  void save(
    BoardRow row,
    Outcome outcome, {
    required bool white,
    String why = '',
  }) {
    busy = true;
    try {
      widget.controller.recordResult(row.game.id, outcome, reason: why);
      if (!mounted) return;
      setState(() => forfeit = false);
      advance(row.game.id, white);
      if (outcome == Outcome.whiteForfeit || outcome == Outcome.blackForfeit) {
        offerWithdraw(
          outcome == Outcome.whiteForfeit ? row.game.black : row.game.white,
        );
      }
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      busy = false;
    }
  }

  void savePending() {
    final (id, outcome, white) = pending!;
    final row = rows().where((r) => r.game.id == id).firstOrNull;
    if (row == null) return;
    if (reason.text.trim().isEmpty) {
      showFailure(context, 'Give a reason for changing this result.');
      return;
    }
    final why = reason.text.trim();
    setState(() => pending = null);
    reason.clear();
    save(row, outcome, white: white, why: why);
  }

  void cancelPending() {
    final white = pending?.$3 ?? true, id = pending?.$1;
    setState(() => pending = null);
    reason.clear();
    if (id != null) focusBox(id, white);
  }

  void offerWithdraw(String absent) {
    final p = widget.controller.event!.player(absent);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${p.name}: withdraw from future rounds?'),
        action: SnackBarAction(
          label: 'Withdraw',
          onPressed: () {
            try {
              widget.controller.savePlayer(
                widget.controller.event!.player(absent).copy(withdrawn: true),
              );
            } catch (e) {
              if (mounted) showFailure(context, e);
            }
          },
        ),
      ),
      snackBarAnimationStyle: AnimationStyle.noAnimation,
    );
  }

  KeyEventResult onKey(BoardRow row, bool white, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final arrow = [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ].contains(event.logicalKey);
    // Holding a result key never enters it twice.
    if (event is KeyRepeatEvent && !arrow) return KeyEventResult.handled;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey, g = row.game;
    if (busy) return KeyEventResult.handled;
    switch (key) {
      case LogicalKeyboardKey.arrowDown ||
          LogicalKeyboardKey.enter ||
          LogicalKeyboardKey.numpadEnter:
        step(g.id, white, HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        step(g.id, white, -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowRight:
        focusBox(g.id, key == LogicalKeyboardKey.arrowLeft);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        if (!forfeit) return KeyEventResult.ignored;
        setState(() => forfeit = false);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        setState(() => forfeit = true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyM:
        menus[g.id]?.open();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
        enter(row, Outcome.unreported, white: white);
        return KeyEventResult.handled;
    }
    // Wins and losses are for the player whose box this is.
    final mine = white ? Outcome.whiteWin : Outcome.blackWin,
        theirs = white ? Outcome.blackWin : Outcome.whiteWin,
        mineF = white ? Outcome.whiteForfeit : Outcome.blackForfeit,
        theirsF = white ? Outcome.blackForfeit : Outcome.whiteForfeit;
    final ch = event.character;
    final Outcome? outcome;
    if (ch == '+' || key == LogicalKeyboardKey.numpadAdd) {
      outcome = mineF;
    } else if (ch == '-' || key == LogicalKeyboardKey.numpadSubtract) {
      outcome = theirsF;
    } else if (ch == '½' ||
        [
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.numpad5,
          LogicalKeyboardKey.keyD,
          LogicalKeyboardKey.equal,
          LogicalKeyboardKey.period,
          LogicalKeyboardKey.numpadDecimal,
        ].contains(key)) {
      if (forfeit) {
        showFailure(
          context,
          'Forfeit: press 1 if this player won, 0 if they lost. Escape cancels.',
        );
        return KeyEventResult.handled;
      }
      outcome = Outcome.draw;
    } else if ([
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.keyW,
    ].contains(key)) {
      outcome = forfeit ? mineF : mine;
    } else if ([
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.numpad0,
      LogicalKeyboardKey.keyL,
    ].contains(key)) {
      outcome = forfeit ? theirsF : theirs;
    } else if (key == LogicalKeyboardKey.keyX) {
      outcome = Outcome.doubleForfeit;
    } else {
      outcome = null;
    }
    if (outcome == null) return KeyEventResult.ignored;
    enter(row, outcome, white: white);
    return KeyEventResult.handled;
  }

  Future<void> assume(String gameId) async {
    await editFields(
      context,
      title: 'Assume a result for pairing',
      description:
          'Use when a game is still going but the next round must be paired. This is not a real result and does not count for points or ratings.',
      fields: const [
        FieldSpec(
          'score',
          'Assume',
          options: {'0.5': 'Draw', '1': 'White wins', '0': 'Black wins'},
        ),
        FieldSpec('reason', 'Reason', required: true),
      ],
      values: const {'score': '0.5'},
      onSave: (values) {
        final outcome = switch (values['score']) {
          '1' => Outcome.whiteWin,
          '0.5' => Outcome.draw,
          '0' => Outcome.blackWin,
          _ => null,
        };
        if (outcome == null) {
          throw const TournamentException('Choose a result.');
        }
        widget.controller.setPairingAssumption(
          gameId,
          outcome,
          values['reason']!,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.controller.event!,
        colors = Theme.of(context).colorScheme,
        all = rows(),
        visible = visibleRows();
    final roundNumbers =
        e.sections.expand((s) => s.rounds).map((r) => r.number).toSet().toList()
          ..sort();
    final shownRound = selectedRound ?? roundNumbers.lastOrNull;
    final byes = <String>[];
    for (final s in e.sections.where(
      (s) => widget.sectionId == null || s.id == widget.sectionId,
    )) {
      final r = selectedRound == null
          ? s.rounds.lastOrNull
          : s.rounds.where((r) => r.number == selectedRound).firstOrNull;
      if (r != null) {
        for (final b in r.byes) {
          byes.add(
            '${e.player(b.player).name} (${halves(b.points)}, ${b.reason.toLowerCase()})',
          );
        }
      }
    }
    // Boards grouped by section, in board order.
    final groups = <Section, List<BoardRow>>{};
    for (final r in visible) {
      groups.putIfAbsent(r.section, () => []).add(r);
    }
    final pendingRow = pending == null
        ? null
        : all.where((r) => r.game.id == pending!.$1).firstOrNull;
    final items = <Widget>[
      for (final entry in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 0, 6),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: entry.key.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text:
                      '   Round ${entry.value.first.round.number} · ${boardRange(entry.key)}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            children: [
              _columns(context),
              for (final row in entry.value) _game(context, row),
            ],
          ),
        ),
      ],
      if (byes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 0, 0),
          child: Text(
            'Byes this round: ${byes.join(' · ')}',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (roundNumbers.isNotEmpty)
                Wrap(
                  spacing: 4,
                  children: [
                    for (final n in roundNumbers)
                      n == shownRound
                          ? FilledButton(
                              key: ValueKey('round-$n'),
                              onPressed: () {},
                              child: Text('Round $n'),
                            )
                          : OutlinedButton(
                              key: ValueKey('round-$n'),
                              onPressed: () {
                                setState(() {
                                  selectedRound = n == roundNumbers.last
                                      ? null
                                      : n;
                                  pending = null;
                                  forfeit = false;
                                });
                                remember();
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => focusFirst(),
                                );
                              },
                              child: Text('Round $n'),
                            ),
                  ],
                ),
              const SizedBox(width: 8),
              FilterChip(
                chipAnimationStyle: noChipAnimation,
                label: const Text('Missing only'),
                selected: missingOnly,
                onSelected: (v) {
                  setState(() => missingOnly = v);
                  remember();
                },
              ),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: jump,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'Go to board'),
                  onSubmitted: (v) {
                    final row = visible
                        .where((r) => r.game.board == int.tryParse(v))
                        .firstOrNull;
                    jump.clear();
                    if (row != null) focusBox(row.game.id, true);
                  },
                ),
              ),
              Text(
                '${all.where((r) => r.game.outcome.resolved).length} of ${all.length} results in',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          color: forfeit ? colors.errorContainer : null,
          child: Text(
            forfeit
                ? 'Forfeit: press 1 if this player won, 0 if they lost. Escape cancels.'
                : 'Click a player\'s box and type  1 won · 0 lost · 5 draw — the opponent\'s box fills in.   + / − forfeit win / loss · X double forfeit · Delete clears · ↑↓ move',
            style: TextStyle(
              fontSize: 13,
              color: forfeit
                  ? colors.onErrorContainer
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
        if (pending case (_, final outcome, _) when pendingRow != null)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border.all(color: colors.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Board ${pendingRow.game.board}, round ${pendingRow.round.number} → ${outcome == Outcome.unreported ? 'no result' : outcome.label}. Later rounds are already paired and stay as they are. Reason:',
                ),
                SizedBox(
                  width: 260,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape):
                          cancelPending,
                    },
                    child: TextField(
                      key: const ValueKey('result-reason'),
                      controller: reason,
                      autofocus: true,
                      onSubmitted: (_) => savePending(),
                    ),
                  ),
                ),
                FilledButton(onPressed: savePending, child: const Text('Save')),
                TextButton(
                  onPressed: cancelPending,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        Expanded(
          child: all.isEmpty
              ? const EmptyState(
                  icon: Icons.grid_view_outlined,
                  title: 'No rounds yet',
                  body: 'Click “Pair next round” to pair the first round.',
                )
              : Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    // Every board is built, so the cursor can move to any
                    // of them.
                    child: SingleChildScrollView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: items,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  static const _board = 44.0, _box = 48.0, _more = 36.0;

  Widget _columns(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: colors.onSurfaceVariant,
        ),
        child: const Row(
          children: [
            SizedBox(width: _board, child: Text('BD')),
            SizedBox(
              width: _box,
              child: Text('RES', textAlign: TextAlign.center),
            ),
            SizedBox(width: 10),
            Expanded(child: Text('WHITE')),
            SizedBox(width: 12),
            Expanded(child: Text('BLACK', textAlign: TextAlign.right)),
            SizedBox(width: 10),
            SizedBox(
              width: _box,
              child: Text('RES', textAlign: TextAlign.center),
            ),
            SizedBox(width: _more),
          ],
        ),
      ),
    );
  }

  Widget _game(BuildContext context, BoardRow row) {
    final e = widget.controller.event!, colors = Theme.of(context).colorScheme;
    final g = row.game;
    final white = e.player(g.white), black = e.player(g.black);
    Widget name(Player p, {required bool right}) => Text.rich(
      TextSpan(
        children: [
          if (right)
            TextSpan(
              text: '${ratingLabel(p)}  ',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'SourceCodePro',
                color: colors.onSurfaceVariant,
              ),
            ),
          TextSpan(
            text: p.name,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          if (!right)
            TextSpan(
              text: '  ${ratingLabel(p)}',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'SourceCodePro',
                color: colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
      textAlign: right ? TextAlign.right : TextAlign.left,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final menu = menus.putIfAbsent(g.id, MenuController.new);
    return GestureDetector(
      key: ValueKey('game-${g.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => focusBox(g.id, true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Semantics(
          label:
              'Round ${row.round.number}, board ${g.board}, ${white.name} versus ${black.name}: ${g.outcome.label}',
          child: Row(
            children: [
              SizedBox(
                width: _board,
                child: Text(
                  '${g.board}${row.section.doubleGames ? '·${g.leg}' : ''}',
                  style: TextStyle(
                    fontFamily: 'SourceCodePro',
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              _scoreBox(context, row, white: true),
              const SizedBox(width: 10),
              Expanded(child: name(white, right: false)),
              const SizedBox(width: 12),
              Expanded(child: name(black, right: true)),
              const SizedBox(width: 10),
              _scoreBox(context, row, white: false),
              SizedBox(
                width: _more,
                child: MenuAnchor(
                  controller: menu,
                  style: const MenuStyle(visualDensity: VisualDensity.compact),
                  menuChildren: [
                    for (final (outcome, label) in [
                      (Outcome.whiteForfeit, 'White wins by forfeit'),
                      (Outcome.blackForfeit, 'Black wins by forfeit'),
                      (Outcome.doubleForfeit, 'Double forfeit'),
                      (Outcome.unfinished, 'Still playing'),
                      (Outcome.disputed, 'Disputed'),
                      (Outcome.unreported, 'Clear result'),
                    ])
                      MenuItemButton(
                        onPressed: () => enter(row, outcome, white: true),
                        child: Text(label),
                      ),
                    const Divider(height: 8),
                    MenuItemButton(
                      onPressed: g.outcome.resolved ? null : () => assume(g.id),
                      child: const Text('Assume a result for pairing only…'),
                    ),
                  ],
                  // Tab goes box to box, never to this button.
                  child: ExcludeFocus(
                    child: IconButton(
                      tooltip: 'Forfeits and other results (M)',
                      icon: const Icon(Icons.more_horiz, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String ratingLabel(Player p) => p.rating == 0 ? 'unr.' : '${p.rating}';

  Widget _scoreBox(BuildContext context, BoardRow row, {required bool white}) {
    final colors = Theme.of(context).colorScheme, g = row.game;
    final node = box(g.id, white), mark = scoreMark(g.outcome, white: white);
    final odd = !g.outcome.resolved && g.outcome != Outcome.unreported;
    return Focus(
      focusNode: node,
      onKeyEvent: (_, event) => onKey(row, white, event),
      onFocusChange: (has) {
        if (!has && forfeit) forfeit = false;
        setState(() {});
      },
      child: Tooltip(
        message: odd ? g.outcome.label : '',
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: GestureDetector(
            key: ValueKey('score-${g.id}-${white ? 'w' : 'b'}'),
            onTap: () => focusBox(g.id, white),
            child: Container(
              width: _box,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surface,
                border: node.hasFocus
                    ? Border.all(color: colors.primary, width: 2)
                    : Border.all(color: colors.outline),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                mark,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: odd ? colors.error : colors.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
