import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/tournament_controller.dart';
import '../domain/model.dart';
import 'dialogs.dart';
import 'history_panel.dart' show historyTime, travel;
import 'players_view.dart'
    show boardRange, halves, PlayerPanel, PlayerPanelState, PlayerDetailsLayout;
import 'panels.dart';
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
  Outcome.unfinished => '',
  Outcome.disputed => '?',
  Outcome.doubleForfeit => '0F',
  _ =>
    '${(white ? o.whiteScore : o.blackScore) == 2 ? 1 : 0}${o.played ? '' : 'F'}',
};

/// Half-points as words: "½ point", "1 point", "2½ points".
String pointsText(int n) =>
    '${halves(n)} ${n == 1 || n == 2 ? 'point' : 'points'}';

/// Each player's score, in half-points, before round [number] of [s].
Map<String, int> scoresBefore(Section s, int number) {
  final scores = <String, int>{for (final id in s.players) id: 0};
  for (final r in s.rounds.where((r) => r.number < number)) {
    for (final b in r.byes) {
      scores[b.player] = (scores[b.player] ?? 0) + b.points;
    }
    for (final g in r.games) {
      scores[g.white] = (scores[g.white] ?? 0) + g.outcome.whiteScore;
      scores[g.black] = (scores[g.black] ?? 0) + g.outcome.blackScore;
    }
  }
  return scores;
}

/// Rounds page, laid out like the wall sheet: a round line with its clock,
/// then one row per board with a score box either side. Typing 1, 0 or 5 in
/// one player's box fills in the other. Earlier rounds open read-only.
class ResultsView extends StatefulWidget {
  const ResultsView({required this.controller, this.sectionId, super.key});
  final TournamentController controller;
  final String? sectionId;
  @override
  State<ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends State<ResultsView> {
  final panel = GlobalKey<PlayerPanelState>();
  String? openPlayerId;
  TournamentController get c => widget.controller;

  void showPlayer(String? id) {
    if (openPlayerId == id) return;
    if (panel.currentState?.commit() == false) return;
    setState(() => openPlayerId = id);
    // Result shortcuts should not fire while inspecting a player.
    FocusManager.instance.primaryFocus?.unfocus();
  }

  final scroll = ScrollController();
  final jump = TextEditingController();
  final reason = TextEditingController();

  /// Score boxes by '$gameId-w' / '$gameId-b'.
  final boxes = <String, FocusNode>{};
  final menus = <String, MenuController>{};
  bool missingOnly = false, forfeit = false, busy = false;

  /// An earlier round on screen; null shows each section's current round.
  /// Never remembered: the page always reopens on the current round.
  int? selectedRound;

  /// Whether results in an earlier round may be changed.
  bool correcting = false;

  /// A result key was pressed on a read-only round.
  bool nudged = false;

  /// Editing pairings: two clicked players swap places.
  bool swapping = false;
  String? swapPick;

  /// The game whose pairing-only assumption is open in the side panel.
  String? assumeFor;
  String roundSignature = '';

  /// A result waiting for a reason, because later rounds are paired:
  /// (game, outcome, typed in White's box).
  (String, Outcome, bool)? pending;
  String get preference => 'results-${widget.sectionId ?? 'all'}';

  @override
  void initState() {
    super.initState();
    roundSignature = signature();
    final saved = c.repository.readPreference(preference);
    if (saved != null) {
      try {
        missingOnly = jsonDecode(saved)['missingOnly'] ?? false;
      } catch (_) {}
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => focusFirst());
  }

  Iterable<Section> get sections => c.event!.sections.where(
    (s) => widget.sectionId == null || s.id == widget.sectionId,
  );

  String signature() =>
      sections.map((s) => '${s.id}:${s.rounds.length}').join('|');

  @override
  void didUpdateWidget(covariant ResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = signature();
    // A round was posted or undone: go back to the current round.
    if (roundSignature.isNotEmpty && next != roundSignature) {
      selectedRound = null;
      correcting = nudged = forfeit = false;
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

  /// The round of [s] on screen.
  Round? shownRound(Section s) => selectedRound == null
      ? s.rounds.lastOrNull
      : s.rounds.where((r) => r.number == selectedRound).firstOrNull;

  /// An earlier round, whose results change only while correcting.
  bool past(BoardRow row) => row.round.number < row.section.rounds.length;
  bool locked(BoardRow row) => past(row) && !correcting;

  List<BoardRow> rows() {
    final result = <BoardRow>[];
    for (final s in sections) {
      final r = shownRound(s);
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

  bool named(Player p) {
    final q = jump.text.trim().toLowerCase();
    return q.isEmpty || p.name.toLowerCase().contains(q);
  }

  List<BoardRow> visibleRows() {
    final q = jump.text.trim();
    final e = c.event!;
    return rows()
        .where(
          (r) =>
              (!missingOnly || !r.game.outcome.resolved) &&
              (q.isEmpty ||
                  '${r.game.board}' == q ||
                  named(e.player(r.game.white)) ||
                  named(e.player(r.game.black))),
        )
        .toList();
  }

  void remember() {
    try {
      c.repository.writePreference(
        preference,
        jsonEncode({'missingOnly': missingOnly}),
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
    final all = visibleRows();
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
    if (locked(row)) {
      setState(() => nudged = true);
      return;
    }
    if (row.game.outcome == outcome) {
      advance(row.game.id, white);
      return;
    }
    if (c.correctionHasDependencies(row.game.id)) {
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
      c.recordResult(row.game.id, outcome, reason: why);
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
    final p = c.event!.player(absent);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${p.name}: withdraw from future rounds?'),
        action: SnackBarAction(
          label: 'Withdraw',
          onPressed: () {
            try {
              c.savePlayer(c.event!.player(absent).copy(withdrawn: true));
            } catch (e) {
              if (mounted) showFailure(context, e);
            }
          },
        ),
      ),
      snackBarAnimationStyle: AnimationStyle.noAnimation,
    );
  }

  /// Shows round [n], or the current round when [n] is the latest.
  void pickRound(int? n, int latest) {
    setState(() {
      selectedRound = n == latest ? null : n;
      correcting = nudged = forfeit = false;
      pending = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => focusFirst());
  }

  void startRounds(List<String> ids) {
    try {
      c.startRounds(ids);
    } catch (e) {
      showFailure(context, e);
    }
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
        if (locked(row)) {
          setState(() => nudged = true);
        } else {
          setState(() => forfeit = true);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyM:
        if (locked(row)) {
          setState(() => nudged = true);
        } else {
          menus[g.id]?.open();
        }
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
      // A forfeit has no draw; the forfeit line already says what to press.
      if (forfeit) return KeyEventResult.handled;
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

  void assume(String gameId) {
    if (panel.currentState?.commit() == false) return;
    setState(() {
      assumeFor = gameId;
      openPlayerId = null;
    });
  }

  Widget assumePanel(String gameId) => FieldsPanel(
    key: ValueKey('assume-$gameId'),
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
    saveLabel: 'Assume for pairing',
    onClose: () => setState(() => assumeFor = null),
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
      c.setPairingAssumption(gameId, outcome, values['reason']!.trim());
    },
  );

  /// First click picks a player; the second swaps the two, saved as a new
  /// pairing revision. Two players on one board swap colours.
  void pickSwap(String id) {
    final a = swapPick;
    if (a == null || a == id) {
      setState(() => swapPick = a == id ? null : id);
      return;
    }
    setState(() => swapPick = null);
    final s = sections.single, r = s.rounds.last, e = c.event!;
    String swapped(String x) => x == a
        ? id
        : x == id
        ? a
        : x;
    try {
      c.replacePairing(s.id, r.number, [
        for (final g in r.games)
          g.copy(white: swapped(g.white), black: swapped(g.black)),
      ], 'Swapped ${e.player(a).name} and ${e.player(id).name}');
    } catch (error) {
      showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = c.event!;
    final roundNumbers =
        sections.expand((s) => s.rounds).map((r) => r.number).toSet().toList()
          ..sort();
    if (selectedRound != null && !roundNumbers.contains(selectedRound)) {
      selectedRound = null;
    }
    final shown = [
      for (final s in sections)
        if (shownRound(s) case final r?) (s, r),
    ];
    final all = rows(), visible = visibleRows();
    final viewingPast = shown.any((x) => x.$2.number < x.$1.rounds.length);
    final latest = roundNumbers.lastOrNull;
    final pendingRow = pending == null
        ? null
        : all.where((r) => r.game.id == pending!.$1).firstOrNull;
    final player = e.players.where((p) => p.id == openPlayerId).firstOrNull;
    if (assumeFor != null && !all.any((r) => r.game.id == assumeFor)) {
      assumeFor = null;
    }
    final single = widget.sectionId == null ? null : shown.singleOrNull;
    if (viewingPast || single == null || single.$2.hasPlay) {
      swapping = false;
      swapPick = null;
    }
    return PlayerDetailsLayout(
      panel: assumeFor != null
          ? assumePanel(assumeFor!)
          : player == null
          ? null
          : PlayerPanel(
              key: panel,
              controller: c,
              player: player,
              onClose: () => showPlayer(null),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (shown.isNotEmpty) ...[
            _roundLine(context, shown, all, roundNumbers),
            _strip(context, shown, viewingPast),
          ],
          if (viewingPast) _pastBanner(context, shown),
          if (swapping) _swapBanner(context, shown.single.$2),
          _legend(context),
          if (pending case (_, final outcome, _) when pendingRow != null)
            _reasonBar(context, pendingRow, outcome),
          Expanded(
            child: roundNumbers.isEmpty
                ? const EmptyState(
                    icon: Icons.grid_view_outlined,
                    title: 'No rounds yet',
                    body:
                        'Post round 1 with the button above. Boards appear here as soon as it is posted.',
                  )
                : visible.isEmpty && !shown.any((x) => x.$2.byes.isNotEmpty)
                ? EmptyState(
                    icon: missingOnly && jump.text.isEmpty
                        ? Icons.check_circle_outline
                        : Icons.search_off,
                    title: missingOnly && jump.text.isEmpty
                        ? 'All results entered'
                        : 'No matching boards',
                    body: missingOnly && jump.text.isEmpty
                        ? 'Turn off Missing only to review them.'
                        : 'Try another name or board number, or turn off Missing only.',
                  )
                : _table(context, shown, visible, latest),
          ),
        ],
      ),
    );
  }

  /// "Round 2 of 3 · Posted 11:02 · Started 11:15 · 7 of 11 in", in the
  /// size of a wall-sheet heading.
  Widget _roundLine(
    BuildContext context,
    List<(Section, Round)> shown,
    List<BoardRow> all,
    List<int> roundNumbers,
  ) {
    final colors = Theme.of(context).colorScheme;
    final numbers = shown.map((x) => x.$2.number).toSet().toList()..sort();
    final planned = shown.map((x) => x.$1.plannedRounds).reduce(math.max);
    final title = numbers.length == 1
        ? 'Round ${numbers.single} of $planned'
        : 'Rounds ${numbers.first}–${numbers.last}';
    final posted = [
      for (final (_, r) in shown)
        if (r.postedAt != null) r.postedAt!,
    ]..sort();
    final started = [
      for (final (_, r) in shown)
        if (r.startedAt != null) r.startedAt!,
    ]..sort();
    final done = all.where((r) => r.game.outcome.resolved).length;
    final complete = shown.every((x) => x.$2.complete);
    final facts = [
      if (posted.isNotEmpty) 'Posted ${historyTime(posted.last)}',
      if (started.length == shown.length)
        'Started ${historyTime(started.first)}'
      else if (complete)
        null
      else if (started.isEmpty)
        'Not started'
      else
        '${started.length} of ${shown.length} sections started',
      complete ? 'All ${all.length} in' : '$done of ${all.length} in',
    ].nonNulls;
    final tabular = const [FontFeature.tabularFigures()];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            header: true,
            child: Text.rich(
              key: const ValueKey('round-line'),
              TextSpan(
                children: [
                  TextSpan(
                    text: title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  TextSpan(
                    text: '   ${facts.join('  ·  ')}',
                    style: TextStyle(
                      fontSize: 18,
                      color: colors.onSurfaceVariant,
                      fontFeatures: tabular,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (roundNumbers.length > 1)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Show round',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                SegmentedButton<int>(
                  key: const ValueKey('round-selector'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: [
                    for (final n in roundNumbers)
                      ButtonSegment(
                        value: n,
                        label: Text('$n'),
                        tooltip: n == roundNumbers.last
                            ? 'Round $n (current)'
                            : 'Round $n (read-only)',
                      ),
                  ],
                  selected: {selectedRound ?? roundNumbers.last},
                  onSelectionChanged: (v) =>
                      pickRound(v.single, roundNumbers.last),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Find, filter, and what to do with the posted round: print it, start
  /// the clock, fix the pairings, or take the post back.
  Widget _strip(
    BuildContext context,
    List<(Section, Round)> shown,
    bool viewingPast,
  ) {
    final waiting = viewingPast
        ? const <String>[]
        : [
            for (final (s, r) in shown)
              if (r.startedAt == null && !r.complete) s.id,
          ];
    final single = widget.sectionId == null ? null : shown.singleOrNull;
    final editable = !viewingPast && single != null && !single.$2.hasPlay;
    final justPosted =
        !viewingPast && (c.undoLabel?.startsWith('Post ') ?? false);
    final search = SizedBox(
      width: 240,
      child: TextField(
        key: const ValueKey('board-search'),
        controller: jump,
        decoration: InputDecoration(
          hintText: 'Find player or board',
          prefixIcon: const Icon(Icons.search, size: 20),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: controlHeight,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: controlHeight,
          ),
          suffixIcon: jump.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  onPressed: () => setState(jump.clear),
                ),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          final first = visibleRows().firstOrNull;
          if (first != null) focusBox(first.game.id, true);
        },
      ),
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (editable && !swapping)
          TextButton(
            key: const ValueKey('edit-pairings'),
            onPressed: () => setState(() {
              swapping = true;
              swapPick = null;
            }),
            child: const Text('Edit pairings'),
          ),
        if (justPosted)
          TextButton(
            key: const ValueKey('undo-post'),
            onPressed: () => travel(
              context,
              c,
              c.graph.back,
              (accept) => c.undo(acceptLosses: accept),
            ),
            child: const Text('Undo post'),
          ),
        OutlinedButton.icon(
          key: const ValueKey('print-round'),
          onPressed: () =>
              showPrint(context, c.event!, sectionId: widget.sectionId),
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('Print packet'),
        ),
        if (waiting.isNotEmpty)
          FilledButton.tonal(
            key: const ValueKey('start-round'),
            onPressed: () => startRounds(waiting),
            child: Text(
              waiting.length == 1 || widget.sectionId != null
                  ? 'Start round'
                  : 'Start round · ${waiting.length} sections',
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              search,
              const SizedBox(width: 12),
              FilterChip(
                chipAnimationStyle: noChipAnimation,
                label: const Text('Missing only'),
                selected: missingOnly,
                onSelected: (v) {
                  setState(() => missingOnly = v);
                  remember();
                },
              ),
            ],
          ),
          actions,
        ],
      ),
    );
  }

  /// Shown while an earlier round is on screen, so nobody enters this
  /// round's results there by mistake.
  Widget _pastBanner(BuildContext context, List<(Section, Round)> shown) {
    final colors = Theme.of(context).colorScheme;
    final number = shown.first.$2.number;
    final current = shown.map((x) => x.$1.rounds.length).reduce(math.max);
    final background = correcting
        ? colors.errorContainer
        : colors.surfaceContainerHigh;
    final foreground = correcting ? colors.onErrorContainer : colors.onSurface;
    return Container(
      key: const ValueKey('past-round-banner'),
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            correcting ? Icons.edit_outlined : Icons.lock_outline,
            size: 18,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              correcting
                  ? 'Correcting round $number. Each change asks for a reason; round $current pairings stay as posted.'
                  : nudged
                  ? 'Round $number is read-only. Choose Correct a result to change it.'
                  : 'Round $number is read-only. Round $current is the current round.',
              style: TextStyle(
                color: foreground,
                fontWeight: nudged && !correcting ? FontWeight.w600 : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (correcting)
            FilledButton(
              onPressed: () => setState(() => correcting = nudged = false),
              child: const Text('Done correcting'),
            )
          else
            OutlinedButton(
              key: const ValueKey('correct-round'),
              onPressed: () => setState(() {
                correcting = true;
                nudged = false;
              }),
              child: const Text('Correct a result'),
            ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => pickRound(null, number),
            child: Text('Back to round $current'),
          ),
        ],
      ),
    );
  }

  Widget _swapBanner(BuildContext context, Round r) {
    final colors = Theme.of(context).colorScheme;
    final picked = swapPick == null ? null : c.event!.player(swapPick!);
    return Container(
      key: const ValueKey('swap-banner'),
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(Icons.swap_horiz, size: 18, color: colors.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              picked == null
                  ? 'Editing round ${r.number} pairings. Click two players to swap them; two on one board swap colours. Each swap saves and can be undone.'
                  : 'Swap ${picked.name} with… click another player, or click ${picked.name} again to cancel.',
              style: TextStyle(color: colors.onSecondaryContainer),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => setState(() {
              swapping = false;
              swapPick = null;
            }),
            child: const Text('Done editing'),
          ),
        ],
      ),
    );
  }

  /// Every key a score box understands, so nothing has to be remembered.
  Widget _legend(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (forfeit) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Forfeit: press 1 if this player won, 0 if they lost. Esc cancels.',
          style: TextStyle(color: colors.onErrorContainer),
        ),
      );
    }
    final key = TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface);
    final keys = [
      ('1 W', 'win'),
      ('0 L', 'loss'),
      ('5 D =', 'draw'),
      ('F', 'forfeit, then 1 or 0'),
      ('+ −', 'forfeit win/loss'),
      ('X', 'double forfeit'),
      ('Del', 'clear'),
      ('M', 'menu'),
      ('↑ ↓', 'board'),
      ('← →', 'player'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
      child: Text.rich(
        key: const ValueKey('result-keys'),
        TextSpan(
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
          children: [
            const TextSpan(text: 'Score box keys:  '),
            for (final (i, (k, what)) in keys.indexed) ...[
              if (i > 0) const TextSpan(text: '   '),
              TextSpan(text: k, style: key),
              TextSpan(text: ' $what'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reasonBar(BuildContext context, BoardRow row, Outcome outcome) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 4, 24, 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Board ${row.game.board}, round ${row.round.number} → ${outcome == Outcome.unreported ? 'no result' : outcome.label}. Later rounds are already paired and stay as they are. Reason:',
          ),
          SizedBox(
            width: 260,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): cancelPending,
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
          TextButton(onPressed: cancelPending, child: const Text('Cancel')),
        ],
      ),
    );
  }

  /// One column header that stays put while the boards scroll under it.
  Widget _table(
    BuildContext context,
    List<(Section, Round)> shown,
    List<BoardRow> visible,
    int? latest,
  ) {
    final colors = Theme.of(context).colorScheme;
    final e = c.event!;
    final bySection = <String, List<BoardRow>>{};
    for (final r in visible) {
      bySection.putIfAbsent(r.section.id, () => []).add(r);
    }
    int firstBoard((Section, Round) x) =>
        x.$2.games.map((g) => g.board).fold(1 << 30, math.min);
    final ordered = [...shown]
      ..sort((a, b) => firstBoard(a).compareTo(firstBoard(b)));
    final items = <Widget>[];
    for (final (s, r) in ordered) {
      final boards = bySection[s.id] ?? const <BoardRow>[];
      final byes = missingOnly
          ? const <ByeAward>[]
          : r.byes.where((b) => named(e.player(b.player))).toList();
      if (boards.isEmpty && byes.isEmpty) continue;
      if (widget.sectionId == null) {
        items.add(_sectionRow(context, s, r));
      }
      for (final b in byes) {
        items.add(_bye(context, b));
      }
      // Swiss boards fall into score groups once anyone has a score.
      final before = s.format == Format.swiss && r.number > 1
          ? scoresBefore(s, r.number)
          : null;
      int group(Game g) =>
          math.max(before?[g.white] ?? 0, before?[g.black] ?? 0);
      final grouped =
          before != null && boards.map((b) => group(b.game)).toSet().length > 1;
      int? last;
      for (final row in boards) {
        if (grouped && group(row.game) != last) {
          last = group(row.game);
          items.add(_scoreGroup(context, last));
        }
        items.add(_game(context, row, before));
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(720.0, constraints.maxWidth);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLowest,
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _columns(context),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scroll,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: items,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static const _board = 72.0, _box = 64.0, _more = 44.0, _row = 52.0;

  Widget _columns(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
        child: const Row(
          children: [
            SizedBox(width: _board, child: Text('Board')),
            SizedBox(
              width: _box,
              child: Text('Score', textAlign: TextAlign.center),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('White')),
            SizedBox(width: 12),
            Expanded(child: Text('Black', textAlign: TextAlign.right)),
            SizedBox(width: 12),
            SizedBox(
              width: _box,
              child: Text('Score', textAlign: TextAlign.center),
            ),
            SizedBox(width: _more),
          ],
        ),
      ),
    );
  }

  /// Section name above its boards when every section is on screen.
  Widget _sectionRow(BuildContext context, Section s, Round r) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: s.name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: [
                '   Round ${r.number} of ${s.plannedRounds}',
                boardRange(s),
                if (r.startedAt != null)
                  'started ${historyTime(r.startedAt!)}'
                else if (r.number == s.rounds.length && !r.complete)
                  'not started',
              ].join(' · '),
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scoreGroup(BuildContext context, int points) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainerLow.withValues(alpha: 0.5),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Text(
        pointsText(points),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }

  /// A bye, listed before the boards like on the wall sheet.
  Widget _bye(BuildContext context, ByeAward b) {
    final colors = Theme.of(context).colorScheme;
    final p = c.event!.player(b.player);
    return Container(
      key: ValueKey('bye-${p.id}'),
      constraints: const BoxConstraints(minHeight: _row),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _board,
            child: Text(
              'Bye',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: _box,
            child: Text(
              halves(b.points),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: InkWell(
                      key: ValueKey('bye-player-${p.id}'),
                      onTap: () => showPlayer(p.id),
                      child: Text(p.name, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                  TextSpan(
                    text:
                        '   ${pointsText(b.points)} · ${b.reason.toLowerCase()}',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _game(BuildContext context, BoardRow row, Map<String, int>? before) {
    final e = c.event!, colors = Theme.of(context).colorScheme;
    final g = row.game;
    final white = e.player(g.white), black = e.player(g.black);
    final lock = locked(row);
    Widget name(Player p, {required bool right}) {
      final score = before?[p.id];
      final label = Text.rich(
        TextSpan(
          children: [
            if (score != null && right)
              TextSpan(
                text: '(${halves(score)})  ',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            TextSpan(text: p.name),
            if (score != null && !right)
              TextSpan(
                text: '  (${halves(score)})',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        style: const TextStyle(fontSize: 18),
        textAlign: right ? TextAlign.right : TextAlign.left,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
      if (swapping) {
        final picked = swapPick == p.id;
        return Semantics(
          selected: picked,
          button: true,
          child: InkWell(
            key: ValueKey('round-player-${g.id}-${p.id}'),
            onTap: () => pickSwap(p.id),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: picked ? colors.primary.withValues(alpha: 0.12) : null,
                border: Border.all(
                  color: picked ? colors.primary : colors.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: label,
            ),
          ),
        );
      }
      return Tooltip(
        message: '${p.name} · Double-click or press Enter for player details',
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): () =>
                showPlayer(p.id),
            const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                showPlayer(p.id),
          },
          child: Semantics(
            button: true,
            hint: 'Opens player details',
            child: InkWell(
              key: ValueKey('round-player-${g.id}-${p.id}'),
              onDoubleTap: () => showPlayer(p.id),
              child: label,
            ),
          ),
        ),
      );
    }

    final menu = menus.putIfAbsent(g.id, MenuController.new);
    return GestureDetector(
      key: ValueKey('game-${g.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => focusBox(g.id, true),
      child: Container(
        constraints: const BoxConstraints(minHeight: _row),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Semantics(
          label:
              'Round ${row.round.number}, board ${g.board}, ${white.name} versus ${black.name}: ${g.outcome.label}${lock ? ', read-only' : ''}',
          child: Row(
            children: [
              SizedBox(
                width: _board,
                child: Text(
                  '${g.board}${row.section.doubleGames ? '·${g.leg}' : ''}',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              _scoreBox(context, row, white: true),
              const SizedBox(width: 12),
              Expanded(child: name(white, right: false)),
              const SizedBox(width: 12),
              Expanded(child: name(black, right: true)),
              const SizedBox(width: 12),
              _scoreBox(context, row, white: false),
              SizedBox(
                width: _more,
                child: MenuAnchor(
                  controller: menu,
                  style: const MenuStyle(visualDensity: VisualDensity.compact),
                  menuChildren: [
                    for (final (outcome, label) in [
                      (Outcome.whiteWin, 'White wins · 1–0'),
                      (Outcome.draw, 'Draw · ½–½'),
                      (Outcome.blackWin, 'Black wins · 0–1'),
                    ])
                      MenuItemButton(
                        onPressed: lock
                            ? null
                            : () => enter(row, outcome, white: true),
                        child: Text(label),
                      ),
                    const Divider(),
                    for (final (outcome, label) in [
                      (Outcome.whiteForfeit, 'White wins by forfeit'),
                      (Outcome.blackForfeit, 'Black wins by forfeit'),
                      (Outcome.doubleForfeit, 'Double forfeit'),
                      (Outcome.unfinished, 'Still playing'),
                      (Outcome.disputed, 'Disputed'),
                      (Outcome.unreported, 'Clear result'),
                    ])
                      MenuItemButton(
                        onPressed: lock
                            ? null
                            : () => enter(row, outcome, white: true),
                        child: Text(label),
                      ),
                    const Divider(height: 8),
                    MenuItemButton(
                      onPressed: lock || g.outcome.resolved
                          ? null
                          : () => assume(g.id),
                      child: const Text('Assume a result for pairing only…'),
                    ),
                  ],
                  // Tab goes box to box, never to this button.
                  child: ExcludeFocus(
                    child: IconButton(
                      tooltip: 'Enter or clear result (M)',
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

  Widget _scoreBox(BuildContext context, BoardRow row, {required bool white}) {
    final colors = Theme.of(context).colorScheme, g = row.game;
    final node = box(g.id, white), lock = locked(row);
    final owner = c.event!.player(white ? g.white : g.black);
    final assumed = !g.outcome.resolved && g.pairingAssumption != null;
    // Unfinished, disputed and assumed results each look different from an
    // empty box, so none of them reads as "not reported yet".
    final (mark, caption) = switch (g.outcome) {
      Outcome.unfinished => ('', 'playing'),
      Outcome.disputed => ('?', 'disputed'),
      _ when assumed => (
        '(${scoreMark(g.pairingAssumption!, white: white)})',
        'assumed',
      ),
      _ => (scoreMark(g.outcome, white: white), null),
    };
    final odd = g.outcome == Outcome.disputed;
    final spoken = switch (g.outcome) {
      Outcome.unreported when assumed =>
        'assumed ${mark.replaceAll(RegExp('[()]'), '')} for pairing only',
      Outcome.unreported => 'no result',
      Outcome.unfinished => 'still playing',
      Outcome.disputed => 'disputed',
      _ => mark,
    };
    return Focus(
      focusNode: node,
      onKeyEvent: (_, event) => onKey(row, white, event),
      onFocusChange: (has) {
        if (!has && forfeit) forfeit = false;
        setState(() {});
      },
      child: Semantics(
        label: '${owner.name}\'s score: $spoken${lock ? ', read-only' : ''}',
        child: Tooltip(
          message: assumed
              ? 'Assumed for pairing only: ${g.pairingReason}'
              : odd
              ? g.outcome.label
              : '',
          child: MouseRegion(
            cursor: lock ? SystemMouseCursors.basic : SystemMouseCursors.text,
            child: GestureDetector(
              key: ValueKey('score-${g.id}-${white ? 'w' : 'b'}'),
              onTap: () => focusBox(g.id, white),
              child: Container(
                width: _box,
                constraints: const BoxConstraints(minHeight: 44),
                padding: EdgeInsets.symmetric(
                  vertical: caption == null ? 8 : 4,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: lock ? colors.surfaceContainerLow : colors.surface,
                  border: node.hasFocus
                      ? Border.all(color: colors.primary, width: 2)
                      : Border.all(color: colors.outline),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      mark,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                        color: odd
                            ? colors.error
                            : assumed
                            ? colors.onSurfaceVariant
                            : colors.onSurface,
                      ),
                    ),
                    if (caption != null)
                      Text(
                        caption,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.1,
                          color: odd ? colors.error : colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
