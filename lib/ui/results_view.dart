import 'result_format.dart';
import 'result_keys.dart';
import 'player_actions.dart';
import 'quad_pairings_panel.dart';
import 'formats/bughouse_panel.dart' show showBughousePartners;
import 'formats/holland_panel.dart';
import '../domain/holland.dart' show isHollandPrelim;
import 'formats/ladder_view.dart';
import '../infrastructure/reports.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';

import '../application/diagnostics.dart';
import '../application/failures.dart';
import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/pairing.dart';
import 'dialogs.dart';
import 'result_correction_panel.dart';
import 'player_panel.dart';
import 'player_format.dart';
import 'side_panel.dart';
import 'players_view.dart';
import 'pairing_review.dart';
import 'pane_controls.dart';
import 'panels.dart';
import 'theme.dart';
import 'workspace_status.dart';

class BoardRow {
  const BoardRow(this.section, this.round, this.game);
  final Section section;
  final Round round;
  final Game game;
}

/// The boards of [round] that have not started: no result and no pairing
/// assumption on any of their games (both games of a double-game board
/// count together), in board order.
List<int> unstartedBoards(Round round) {
  final started = {
    for (final g in round.games)
      if (g.outcome != Outcome.unreported || g.pairingAssumption != null)
        g.board,
  };
  return {
    for (final g in round.games)
      if (!started.contains(g.board)) g.board,
  }.toList()..sort();
}

/// Pairings and results, laid out like the wall sheet: round and result count,
/// then one row per board with a score box either side. Typing 1/W, 0/L or D in
/// one player's box fills in the other. Earlier rounds open read-only.
class ResultsView extends StatefulWidget {
  const ResultsView({
    required this.controller,
    this.sectionId,
    this.roundAction,
    this.onAddPlayers,
    this.onNewSection,
    super.key,
  });
  final TournamentController controller;
  final String? sectionId;
  final Widget? roundAction;

  /// Where the empty page sends the director next: the Players page while
  /// the event has no players, and creating a section once it has. Each
  /// button is shown only when its callback is given.
  final VoidCallback? onAddPlayers, onNewSection;
  @override
  State<ResultsView> createState() => ResultsViewState();
}

class ResultsViewState extends State<ResultsView> {
  final panel = GlobalKey<PlayerPanelState>();
  String? openPlayerId;

  /// Where the open player panel should start, such as `byes`.
  String? openFocus;
  TournamentController get c => widget.controller;

  /// Edits pending in the open player card are applied before the card is
  /// closed or replaced. False when they cannot be saved: the card then
  /// stays open on its error and nothing else happens.
  bool applyCardEdits() => panel.currentState?.applyEdits() ?? true;

  void showPlayer(String? id, {String? focus}) {
    if (!applyCardEdits()) return;
    if (id != null) {
      Dock.maybeOf(context)?.claim(panelOwner);
    } else if (Dock.maybeOf(context)?.id == panelOwner) {
      Dock.maybeOf(context)?.close();
    }
    setState(() {
      openPlayerId = id;
      openFocus = focus;
      assumeFor = null;
      repairing = false;
    });
    // Result shortcuts should not fire while inspecting a player.
    FocusManager.instance.primaryFocus?.unfocus();
  }

  final scroll = ScrollController();
  final jump = TextEditingController();

  /// Why the boards not started are being paired again, and the boards the
  /// director says have started; both outlive closing the panel.
  final repairReason = TextEditingController();
  final repairStarted = <int>{};

  /// Score boxes by '$gameId-w' / '$gameId-b'.
  final boxes = <String, FocusNode>{};
  bool busy = false;
  bool get missingOnly =>
      c.workspaceState.read('pairings-missing-only') == 'true';
  final crosstableHeading = GlobalKey();
  final stackedScroll = ScrollController();

  /// An earlier round on screen; null shows each section's current round.
  /// Restored read-only; a newly posted round resets the selection.
  int? selectedRound;
  bool showAllRounds = false;

  /// The default view: a fixed quad schedule shows every round, while
  /// Swiss sections beside it stay on their current round.
  bool scheduleRounds = true;

  /// Every board was entered; focus rests on the completion status.
  bool allEntered = false;
  final doneNode = FocusNode(debugLabel: 'all results entered');

  /// A printable key that is not a result was typed; the legend says which
  /// keys are.
  bool invalidKey = false;

  /// The last key was a draw, playing or disputed key on a forfeit board.
  bool forfeitRefused = false;

  /// The last key was 5, = or a decimal point: the legend leads with the
  /// draw key.
  bool drawHint = false;

  /// The one score box Tab enters the grid at.
  String? entryBox;
  void showCrosstable() {
    final target = crosstableHeading.currentContext;
    if (target != null) Scrollable.ensureVisible(target);
  }

  /// Whether results in an earlier round may be changed.
  bool correcting = false;

  /// A result key was pressed on a read-only round.
  bool nudged = false;

  /// Editing pairings: two clicked players swap places.
  bool swapping = false;
  String? swapPick;

  /// The game whose pairing-only assumption is open in the side panel.
  String? assumeFor;

  /// Re-pairing the boards not started is open in the side panel.
  bool repairing = false;
  String roundSignature = '';

  String get preference => 'results-${widget.sectionId ?? 'all'}';
  String get panelOwner => 'results-panel-${widget.sectionId ?? 'all'}';
  String? activeBox;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    showAllRounds = allQuads;
    roundSignature = signature();
    final saved = c.workspaceState.readMap(preference);
    if (c.workspaceState.read('pairings-missing-only') == null) {
      c.workspaceState.write(
        'pairings-missing-only',
        '${saved['missingOnly'] == true}',
      );
    }
    if (saved['signature'] == roundSignature) {
      selectedRound = saved['round'] as int?;
      showAllRounds = saved['allRounds'] == true;
      scheduleRounds = saved['scheduleRounds'] != false;
      jump.text = saved['search'] as String? ?? '';
      activeBox = saved['box'] as String?;
      scrollOffset = (saved['scroll'] as num? ?? 0).toDouble();
    }
    ready = true;
    jump.addListener(remember);
    scroll.addListener(scrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = activeBox;
      final node = key == null ? null : boxes[key];
      if (node?.context != null) {
        node!.requestFocus();
      } else {
        focusFirst();
      }
      if (scroll.hasClients && saved['signature'] == roundSignature) {
        scroll.jumpTo(
          (saved['scroll'] as num? ?? 0).toDouble().clamp(
            0,
            scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    remember();
  }

  void printRound() => showPrint(
    context,
    c.event!,
    sectionId: widget.sectionId,
    roundNumber: sections.every(hasFixedQuadSchedule) ? null : selectedRound,
    kind: ReportKind.packet,
  );

  Iterable<Section> get sections => c.pairingEvent.sections.where(
    (s) => widget.sectionId == null || s.id == widget.sectionId,
  );

  bool get allQuads =>
      sections.isNotEmpty && sections.every(hasFixedQuadSchedule);

  String signature() =>
      sections.map((s) => '${s.id}:${s.rounds.length}').join('|');

  @override
  void didUpdateWidget(covariant ResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = signature();
    // A round was posted or undone: go back to the current round.
    if (roundSignature.isNotEmpty && next != roundSignature) {
      selectedRound = null;
      showAllRounds = allQuads;
      scheduleRounds = true;
      correcting = nudged = allEntered = invalidKey = false;
      activeBox = null;
      jump.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (scroll.hasClients) scroll.jumpTo(0);
        focusFirst();
      });
    }
    roundSignature = next;
    remember();
  }

  @override
  void dispose() {
    remember();
    scrollSave?.cancel();
    ready = false;
    for (final n in boxes.values) {
      n.dispose();
    }
    doneNode.dispose();
    scroll.dispose();
    stackedScroll.dispose();
    jump.dispose();
    repairReason.dispose();
    super.dispose();
  }

  FocusNode box(String gameId, bool white) =>
      boxes.putIfAbsent('$gameId-${white ? 'w' : 'b'}', () {
        final node = FocusNode(
          debugLabel: 'score $gameId ${white ? 'white' : 'black'}',
        );
        node.addListener(() {
          if (node.hasFocus) {
            activeBox = '$gameId-${white ? 'w' : 'b'}';
            invalidKey = false;
            // Back on a board: the status line names it again.
            allEntered = false;
            remember();
          }
        });
        return node;
      });

  /// The round of [s] on screen.
  Round? shownRound(Section s) => selectedRound == null
      ? s.rounds.lastOrNull
      : s.rounds.where((r) => r.number == selectedRound).firstOrNull;

  /// Whether every round of [s] is on screen. A quad's fixed schedule never
  /// turns a Swiss section beside it into an earlier round.
  bool allRoundsOf(Section s) =>
      showAllRounds ||
      (scheduleRounds && selectedRound == null && hasFixedQuadSchedule(s));

  Iterable<Round> shownRounds(Section s) =>
      allRoundsOf(s) ? s.rounds : [?shownRound(s)];

  /// An earlier round, whose results change only while correcting.
  bool earlier(Section s, Round r) =>
      s.format == Format.swiss && r.number < s.rounds.length;
  bool past(BoardRow row) => earlier(row.section, row.round);
  bool locked(BoardRow row) => past(row) && !correcting;

  List<BoardRow> rows() {
    final result = <BoardRow>[];
    for (final s in sections) {
      for (final r in shownRounds(s)) {
        for (final g in r.games) {
          result.add(BoardRow(s, r, g));
        }
      }
    }
    result.sort((a, b) {
      final round = a.round.number.compareTo(b.round.number);
      if (round != 0) return round;
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

  /// The last scroll offset, kept after the list detaches on dispose.
  double scrollOffset = 0;
  Timer? scrollSave;

  /// Scrolling only notes the offset; it is saved once scrolling settles,
  /// not written and broadcast on every frame.
  void scrolled() {
    if (scroll.hasClients) scrollOffset = scroll.offset;
    scrollSave?.cancel();
    scrollSave = Timer(const Duration(milliseconds: 400), remember);
  }

  /// What was last saved, so a focus change or rebuild that alters nothing
  /// costs no write.
  String? remembered;

  void remember() {
    if (!ready) return;
    scrollSave?.cancel();
    scrollSave = null;
    final state = {
      'signature': roundSignature,
      'round': selectedRound,
      'allRounds': showAllRounds,
      'scheduleRounds': scheduleRounds,
      'search': jump.text,
      'box': activeBox,
      'scroll': scroll.hasClients ? scroll.offset : scrollOffset,
    };
    final next = '$state';
    if (next == remembered) return;
    if (c.workspaceState.writeMap(preference, state)) remembered = next;
  }

  /// Where each board sits in the list of rows last drawn (section
  /// headings, score groups and byes included), and how many rows there are.
  Map<String, int> _itemOf = const {};
  int _itemCount = 0;

  /// Whether [node]'s box is on screen now. The boards are a lazy list, and
  /// a node keeps the context of a row the list has since dropped, so only
  /// a mounted context counts.
  static bool _built(FocusNode node) => node.context?.mounted ?? false;

  void focusBox(String gameId, bool white, [int tries = 8]) {
    final node = box(gameId, white);
    if (!_built(node)) {
      if (tries > 0) {
        // A board scrolled away, or never reached, has no box yet. Jump to
        // where it should be. Either way the row may simply not be drawn
        // yet, so look again once the sheet has been built.
        if (scroll.hasClients) {
          if (_itemOf[gameId] case final index?) {
            scroll.position.jumpTo(_offsetNear(index));
          }
        }
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => mounted ? focusBox(gameId, white, tries - 1) : null,
        );
        return;
      }
      // Out of reach: never leave the cursor on the board just entered,
      // where the next key would change its result, and never ask a
      // dropped box for focus, which it would take later at random.
      if (boxes.values.any((n) => n.hasPrimaryFocus)) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
      return;
    }
    node.requestFocus();
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

  /// The scroll offset that brings row [target] into view, a third of the
  /// way down. Worked out from the boards on screen now, whose positions
  /// and spacing are measured, so a long round with headings, score groups
  /// and byes between the boards is reached in a jump or two.
  double _offsetNear(int target) {
    final position = scroll.position;
    final anchors = <(int, double)>[];
    for (final MapEntry(key: id, value: index) in _itemOf.entries) {
      // Only rows still on the list: a dropped row's context is defunct.
      final row = boxes['$id-w']?.context;
      if (row == null || !row.mounted) continue;
      final object = row.findRenderObject();
      if (object == null || !object.attached) continue;
      final viewport = RenderAbstractViewport.maybeOf(object);
      if (viewport == null) continue;
      anchors.add((index, viewport.getOffsetToReveal(object, 0).offset));
    }
    final lead = position.viewportDimension / 3;
    double offset;
    if (anchors.length >= 2) {
      anchors.sort((a, b) => a.$1.compareTo(b.$1));
      final (first, firstAt) = anchors.first;
      final (last, lastAt) = anchors.last;
      final perRow = (lastAt - firstAt) / math.max(1, last - first);
      final (from, fromAt) = target < first ? anchors.first : anchors.last;
      offset = fromAt + (target - from) * perRow - lead;
    } else {
      final total = position.maxScrollExtent + position.viewportDimension;
      offset = total * target / math.max(1, _itemCount) - lead;
    }
    return offset.clamp(position.minScrollExtent, position.maxScrollExtent);
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

  /// After a result: the next board still missing one, same side, in the
  /// [order] the boards had before the save (Missing only hides the board
  /// just entered), wrapping to an earlier skipped board. With none left,
  /// focus moves to the completion status so the next key changes nothing.
  /// Clearing a result keeps the cursor where it is.
  void advance(
    String gameId,
    bool white,
    Outcome outcome, {
    List<String>? order,
  }) {
    if (outcome == Outcome.unreported) {
      focusBox(gameId, white);
      return;
    }
    final ids = order ?? [for (final r in visibleRows()) r.game.id];
    final open = {
      for (final r in rows())
        if (!r.game.outcome.resolved) r.game.id,
    };
    final i = ids.indexOf(gameId);
    final next = [
      ...ids.skip(i + 1),
      ...ids.take(math.max(i, 0)),
    ].where(open.contains).firstOrNull;
    if (next != null) {
      focusBox(next, white);
      return;
    }
    setState(() => allEntered = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) doneNode.requestFocus();
    });
  }

  /// A key on a score box applies at once. Replacing or clearing a result
  /// already recorded says so in a notice with Undo (see [save]); where
  /// later rounds depend on the result, the review opens beside the table
  /// before anything is committed.
  void enter(BoardRow row, Outcome outcome, {required bool white}) {
    if (busy) return;
    if (locked(row)) {
      setState(() => nudged = true);
      return;
    }
    if (row.game.outcome == outcome) {
      advance(row.game.id, white, outcome);
      return;
    }
    if (c.correctionHasDependencies(row.game.id)) {
      // Later rounds depend on this result, so it opens beside the table.
      openResultCorrection(
        context,
        c,
        row.game.id,
        outcome: outcome,
        white: white,
        onDone: () {
          if (mounted) focusBox(row.game.id, white);
        },
      );
      return;
    }
    save(row, outcome, white: white);
  }

  /// What replacing the result of [row] did, for the notice with Undo:
  /// "Board 7 was 1–0, now ½–½", led by the section when every section is
  /// on screen and by the round when more than the current one is.
  String overwriteNotice(BoardRow row, Outcome before, Outcome now) => [
    if (widget.sectionId == null) row.section.name,
    if (allRoundsOf(row.section) ||
        row.round.number != row.section.rounds.length)
      'Round ${row.round.number}',
    resultChangeText(row.game.board, before, now),
  ].join(' · ');

  void save(
    BoardRow row,
    Outcome outcome, {
    required bool white,
    String why = '',
  }) {
    busy = true;
    final order = [for (final r in visibleRows()) r.game.id];
    final before = row.game.outcome;
    try {
      c.recordResult(row.game.id, outcome, reason: why);
    } catch (e) {
      if (mounted) showFailure(context, e);
      return;
    } finally {
      busy = false;
    }
    // A recorded result was replaced or cleared by one key: never silently.
    if (mounted && before != Outcome.unreported && before != outcome) {
      showUndoNotice(context, c, overwriteNotice(row, before, outcome));
    }
    // Saved. Moving the cursor is separate, so a problem finding the next
    // board is never reported as a result that failed to save; it is
    // logged, and the cursor stays where it was.
    if (!mounted) return;
    setState(() {});
    try {
      advance(row.game.id, white, outcome, order: order);
    } catch (error, stack) {
      Diagnostics.record(
        'advance cursor',
        'failed',
        context: {'game': row.game.id},
        error: error,
        stack: stack,
      );
    }
  }

  /// Shows round [n], or the current round when [n] is the latest.
  void pickRound(int? n, int latest) {
    setState(() {
      selectedRound = n == latest ? null : n;
      showAllRounds = scheduleRounds = false;
      correcting = nudged = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => focusFirst());
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
    // By position on a keyboard layout without Latin letters.
    final key = commandKey(event), g = row.game;
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
      case LogicalKeyboardKey.keyA:
        if (!locked(row) && !g.outcome.resolved) assume(g.id);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        showPlayer(white ? g.white : g.black);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f2:
        // An explicit correction, also of an earlier round: the review
        // opens beside the table.
        if (g.outcome != Outcome.unreported) {
          openResultCorrection(
            context,
            c,
            g.id,
            white: white,
            onDone: () {
              if (mounted) focusBox(g.id, white);
            },
          );
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
        enter(row, Outcome.unreported, white: white);
        return KeyEventResult.handled;
    }
    final outcome = resultFromKey(
      event,
      white: white,
      current: row.game.outcome,
    );
    if (outcome == null) {
      // A printable key that is not a result: say which keys are. 5, = and
      // the decimal point are answered with the draw key, whether or not
      // the key carries a character (the numpad decimal may not).
      final draw = isDrawAttempt(event);
      if (draw || (event.character ?? '').trim().isNotEmpty) {
        setState(() {
          invalidKey = true;
          forfeitRefused = refusedOnForfeit(event, g.outcome);
          drawHint = draw;
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (invalidKey) setState(() => invalidKey = false);
    enter(row, outcome, white: white);
    return KeyEventResult.handled;
  }

  void assume(String gameId) {
    if (!applyCardEdits()) return;
    setState(() {
      Dock.maybeOf(context)?.claim(panelOwner);
      assumeFor = gameId;
      openPlayerId = null;
      repairing = false;
    });
  }

  /// The boards of the round on screen that have not started (no result
  /// and no pairing assumption on any of their games), when they can be
  /// paired again on their own: one section's latest round, in a US Chess
  /// Swiss. Null where that does not apply.
  ({Section section, Round round, List<int> boards})? repairable(
    List<(Section, Round)> shown,
  ) {
    final only = widget.sectionId == null ? null : shown.singleOrNull;
    if (only == null) return null;
    final (s, r) = only;
    if (pairingFormat(s) != Format.swiss ||
        s.fideRated ||
        r.number != s.rounds.length ||
        r.games.isEmpty) {
      return null;
    }
    return (section: s, round: r, boards: unstartedBoards(r));
  }

  /// Opens re-pairing beside the boards. The reason starts as the
  /// withdrawal that usually prompts it, for the director to change.
  void openRepair(Round round) {
    if (!applyCardEdits()) return;
    if (repairReason.text.trim().isEmpty) {
      final e = c.event!, waiting = unstartedBoards(round).toSet();
      final gone = {
        for (final g in round.games.where((g) => waiting.contains(g.board)))
          for (final id in [g.white, g.black])
            if (e.player(id).withdrawn) e.player(id).name,
      };
      if (gone.isNotEmpty) repairReason.text = '${gone.join(', ')} withdrew';
    }
    setState(() {
      Dock.maybeOf(context)?.claim(panelOwner);
      repairing = true;
      assumeFor = null;
      openPlayerId = null;
      swapping = false;
      swapPick = null;
    });
  }

  void closeRepair() {
    Dock.maybeOf(context)?.close();
    setState(() => repairing = false);
  }

  Widget assumePanel(String gameId) {
    // C.04.2 3.1: a FIDE section pairs an unfinished game as a draw.
    final fide = c.event!.sections.any(
      (s) =>
          s.fideRated &&
          s.rounds.any((r) => r.games.any((g) => g.id == gameId)),
    );
    return FieldsPanel(
      key: ValueKey('assume-$gameId'),
      controller: c,
      draftKey: 'draft-assume-$gameId',
      title: 'Assume a result for pairing',
      description: fide
          ? 'Use when a game is still going but the next round must be paired. FIDE pairs it as a draw; it does not count for points or ratings.'
          : 'Use when a game is still going but the next round must be paired. This is not a real result and does not count for points or ratings.',
      fields: [
        FieldSpec(
          'score',
          'Assume',
          options: fide
              ? const {'0.5': 'Draw'}
              : const {'0.5': 'Draw', '1': 'White wins', '0': 'Black wins'},
        ),
        const FieldSpec('reason', 'Reason', required: true),
      ],
      values: const {'score': '0.5'},
      saveLabel: 'Assume for pairing',
      onClose: () {
        Dock.maybeOf(context)?.close();
        setState(() => assumeFor = null);
      },
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
  }

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
    // A ladder has no rounds to show: its own view records challenge games.
    if (e.sections.where((s) => s.id == widget.sectionId).firstOrNull
        case final ladder? when ladder.format == Format.ladder) {
      return LadderView(controller: c, section: ladder);
    }
    final roundNumbers =
        sections.expand((s) => s.rounds).map((r) => r.number).toSet().toList()
          ..sort();
    if (selectedRound != null && !roundNumbers.contains(selectedRound)) {
      selectedRound = null;
    }
    final shown = [
      for (final s in sections)
        for (final r in shownRounds(s)) (s, r),
    ];
    final all = rows(), visible = visibleRows();
    // Tab enters the grid at the active box, or the first board missing a
    // result; every other box is reached with the arrows.
    final keys = {
      for (final r in visible) ...['${r.game.id}-w', '${r.game.id}-b'],
    };
    final start =
        visible.where((r) => !r.game.outcome.resolved).firstOrNull ??
        visible.firstOrNull;
    entryBox = keys.contains(activeBox)
        ? activeBox
        : start == null
        ? null
        : '${start.game.id}-w';
    // Any earlier Swiss round on screen: its boards are read-only, while
    // other sections' boards beside it stay open for entry.
    final viewingPast = shown.any((x) => earlier(x.$1, x.$2));
    final latest = roundNumbers.lastOrNull;
    final player = e.players.where((p) => p.id == openPlayerId).firstOrNull;
    if (assumeFor != null && !all.any((r) => r.game.id == assumeFor)) {
      assumeFor = null;
    }
    final repair = repairable(shown);
    if (repair == null) repairing = false;
    final single = widget.sectionId == null ? null : shown.singleOrNull;
    if (viewingPast || single == null || single.$2.hasPlay) {
      swapping = false;
      swapPick = null;
    }
    final boardHeading = _roundLine(
      context,
      shown,
      all,
      roundNumbers,
      viewingPast,
    );
    // Always present, so the boards start at the same height in every
    // section whether or not it has pairings yet.
    final boardToolbar = _strip(context, shown, viewingPast, repair);
    // Notices belong to the boards, so they sit in the boards pane and never
    // push the crosstable beside it down.
    final notices = [
      for (final s in sections)
        if (c.quadScheduleIssues[s.id] case final issue?)
          _scheduleIssue(context, s, issue),
      if (swapping) _swapBanner(context, shown.single.$2),
      if (repair != null) ?_withdrawnNotice(context, repair.round),
    ];
    if (allEntered && !visible.every((r) => r.game.outcome.resolved)) {
      allEntered = false;
    }
    final boardTable = e.players.isEmpty || sections.isEmpty
        ? _nothingToPair(context)
        : roundNumbers.isEmpty
        ? _blankTable(context)
        : visible.isEmpty && !shown.any((x) => x.$2.byes.isNotEmpty)
        ? _noBoards(context)
        : _table(context, shown, visible, latest);
    return PlayerDetailsLayout(
      expandContent: true,
      panel:
          Dock.maybeOf(context) != null &&
              Dock.maybeOf(context)!.id != panelOwner
          ? null
          : assumeFor != null
          ? assumePanel(assumeFor!)
          : repairing
          ? RepairPanel(
              key: ValueKey('repair-${repair!.section.id}'),
              controller: c,
              sectionId: repair.section.id,
              reason: repairReason,
              started: repairStarted,
              onClose: closeRepair,
            )
          : player == null
          ? null
          : PlayerPanel(
              key: panel,
              controller: c,
              player: player,
              focusField: openFocus,
              onClose: () => showPlayer(null),
            ),
      child: LayoutBuilder(
        builder: (context, layout) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          // A wide gutter with a hairline keeps the two tables distinct.
          const gutter = 40.0;
          final split = layout.maxWidth >= 1040 * scale + gutter;
          // Each pane takes half of a wide window, so long names fit, up to
          // a width a row is still easy to read across.
          final paneWidth = math.min(
            (layout.maxWidth - gutter) / 2,
            _widestPane * scale,
          );
          final divider = SizedBox(
            width: gutter,
            child: Center(
              child: VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          );
          final standings = PlayersView(
            key: ValueKey('crosstable-${widget.sectionId}'),
            controller: c,
            sectionId: widget.sectionId,
            standingsOnly: true,
            onPlayer: showPlayer,
            standingsLayout: (heading, toolbar, table) {
              final crossHeading = KeyedSubtree(
                key: crosstableHeading,
                child: heading,
              );
              if (!split) {
                return SingleChildScrollView(
                  key: const ValueKey('pairings-stacked'),
                  controller: stackedScroll,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: math.min(layout.maxWidth, _widestPane * scale),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          boardHeading,
                          boardToolbar,
                          ...notices,
                          boardTable,
                          const SizedBox(height: 24),
                          crossHeading,
                          toolbar,
                          table,
                        ],
                      ),
                    ),
                  ),
                );
              }
              Widget sharedRow(Widget left, Widget right) => IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: paneWidth, child: left),
                    divider,
                    SizedBox(width: paneWidth, child: right),
                  ],
                ),
              );
              return Column(
                key: const ValueKey('pairings-split'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: layout.maxHeight * 0.6,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          sharedRow(crossHeading, boardHeading),
                          sharedRow(toolbar, boardToolbar),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: paneWidth, child: table),
                        divider,
                        SizedBox(
                          width: paneWidth,
                          child: notices.isEmpty
                              ? boardTable
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ...notices,
                                    Expanded(child: boardTable),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.roundAction != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: widget.roundAction!,
                  ),
                ),
              Expanded(child: standings),
            ],
          );
        },
      ),
    );
  }

  /// Compact round heading beside the crosstable heading.
  Widget _roundLine(
    BuildContext context,
    List<(Section, Round)> shown,
    List<BoardRow> all,
    List<int> roundNumbers,
    bool viewingPast,
  ) {
    final colors = Theme.of(context).colorScheme;
    final numbers = shown.map((x) => x.$2.number).toSet().toList()..sort();
    final planned = [
      for (final s in shown.isEmpty ? sections : shown.map((x) => x.$1))
        s.plannedRounds,
    ].fold(0, math.max);
    final title = numbers.isEmpty
        ? planned == 0
              ? 'Round 1'
              : 'Round 1 of $planned'
        : showAllRounds
        ? 'All rounds'
        : numbers.length == 1
        ? 'Round ${numbers.single} of $planned'
        : 'Rounds ${numbers.first}–${numbers.last}';
    final done = all.where((r) => r.game.outcome.resolved).length;
    final complete = shown.every((x) => x.$2.complete);
    final facts = [
      if (numbers.isEmpty)
        'Not paired yet'
      else ...[
        if (showAllRounds) '${numbers.length} rounds',
        complete
            ? 'All ${all.length} results in'
            : '$done of ${all.length} results in',
      ],
    ];
    final tabular = const [FontFeature.tabularFigures()];
    // Every piece of the heading is one control tall, so when the chips wrap
    // the title still sits on the same line as the Crosstable title beside it.
    final band = BoxConstraints(
      minHeight: MediaQuery.textScalerOf(context).scale(controlHeight),
    );
    Widget line(Widget child) => ConstrainedBox(
      constraints: band,
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        heightFactor: 1,
        child: child,
      ),
    );
    return PaneHeading(
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          line(
            Semantics(
              header: true,
              child: Text.rich(
                key: const ValueKey('round-line'),
                TextSpan(
                  children: [
                    TextSpan(
                      text: title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    TextSpan(
                      text: '   ${facts.join('  ·  ')}',
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.onSurfaceVariant,
                        fontFeatures: tabular,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // An earlier round says so in words beside its title; the way in
          // (Correct a result) and out (Done correcting) is in the toolbar.
          if (viewingPast) line(_pastStatus(context, shown)),
          // Bughouse pairs partnerships: form them here before round 1.
          if (numbers.isEmpty)
            for (final s
                in sections
                    .where(
                      (s) => s.format == Format.bughouse && s.rounds.isEmpty,
                    )
                    .take(1))
              line(
                TextButton(
                  key: const ValueKey('bughouse-partners'),
                  onPressed: () =>
                      showBughousePartners(context, c, sectionId: s.id),
                  child: const Text('Partners'),
                ),
              ),
          // The round chips share the title's line, so a section with them
          // is no taller than one without.
          if (roundNumbers.length > 1)
            Semantics(
              label: 'Show round',
              container: true,
              child: Wrap(
                key: const ValueKey('round-selector'),
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final n in roundNumbers)
                    ChoiceChip(
                      label: Text('$n'),
                      showCheckmark: false,
                      selected:
                          !showAllRounds &&
                          (selectedRound ?? roundNumbers.last) == n,
                      onSelected: (_) => pickRound(n, roundNumbers.last),
                    ),
                  ChoiceChip(
                    key: const ValueKey('all-rounds'),
                    label: const Text('All'),
                    showCheckmark: false,
                    selected: showAllRounds,
                    onSelected: (_) => setState(() {
                      showAllRounds = true;
                      selectedRound = null;
                      correcting = nudged = false;
                    }),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Find boards, filter missing results, edit pairings, and print.
  Widget _strip(
    BuildContext context,
    List<(Section, Round)> shown,
    bool viewingPast,
    ({Section section, Round round, List<int> boards})? repair,
  ) {
    final single = widget.sectionId == null ? null : shown.singleOrNull;
    final quad = sections.where(hasFixedQuadSchedule).singleOrNull;
    final editable = !viewingPast && single != null && !single.$2.hasPlay;
    final search = SearchField(
      key: const ValueKey('board-search'),
      controller: jump,
      enabled: shown.isNotEmpty,
      onChanged: () => setState(() {}),
      onSubmitted: () {
        final first = visibleRows().firstOrNull;
        if (first != null) focusBox(first.game.id, true);
      },
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          search,
          // A finished Holland prelim offers its final from here.
          if (sections
                  .where((s) => s.id == widget.sectionId && isHollandPrelim(s))
                  .firstOrNull
              case final prelim?)
            HollandFinalsAction(c, prelim),
          if (viewingPast && correcting)
            OutlinedButton(
              key: const ValueKey('done-correcting'),
              onPressed: () => setState(() => correcting = nudged = false),
              child: const Text('Done correcting'),
            )
          else if (viewingPast)
            OutlinedButton(
              key: const ValueKey('correct-round'),
              onPressed: () => setState(() {
                correcting = true;
                nudged = false;
              }),
              child: const Text('Correct a result'),
            )
          else if ((quad != null || editable) && !swapping)
            TextButton(
              key: const ValueKey('edit-pairings'),
              onPressed: quad != null
                  ? () => showQuadPairingsEditor(context, c, sectionId: quad.id)
                  : () => setState(() {
                      swapping = true;
                      swapPick = null;
                    }),
              child: const Text('Edit pairings'),
            ),
          // Stays in place, greyed, once every board has started, so the
          // toolbar does not reflow under the last result being typed.
          if (repair != null)
            Tooltip(
              message: repair.boards.isEmpty
                  ? 'Every board has a result or has started'
                  : 'Pair the boards that have not started again, as after a withdrawal',
              child: TextButton(
                key: const ValueKey('repair-unstarted'),
                onPressed: repair.boards.isEmpty
                    ? null
                    : () => openRepair(repair.round),
                child: const Text('Re-pair unstarted boards'),
              ),
            ),
          FilterChip(
            chipAnimationStyle: noChipAnimation,
            label: const Text('Missing only'),
            selected: missingOnly,
            onSelected: shown.isEmpty
                ? null
                : (v) => setState(
                    () => c.workspaceState.write('pairings-missing-only', '$v'),
                  ),
          ),
          IconButton(
            key: const ValueKey('print-round'),
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
            tooltip: sections.every(hasFixedQuadSchedule)
                ? 'Print pairings and result sheets'
                : showAllRounds
                ? 'Print pairings and result sheets for the current round'
                : 'Print pairings and result sheets for this round',
            onPressed: shown.isEmpty ? null : printRound,
            icon: const Icon(Icons.print_outlined, size: 18),
          ),
        ],
      ),
    );
  }

  /// Where focus rests after the last missing result, so the next key
  /// cannot overwrite a board. Announced as it appears. It sits in the
  /// status line under the boards, which is always there, so nothing moves
  /// when the last result goes in.
  Widget _allEntered(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final every = rows().every((r) => r.game.outcome.resolved);
    return Focus(
      focusNode: doneNode,
      onFocusChange: (_) => setState(() {}),
      child: Semantics(
        liveRegion: true,
        child: Container(
          key: const ValueKey('all-results-entered'),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(
              color: doneNode.hasFocus ? focusRing(colors) : Colors.transparent,
              width: focusRingWidth,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 16,
                color: colors.onSurface,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  every ? 'All results entered' : 'All matching boards entered',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// In place of the boards when none are listed. With Missing only on,
  /// the last result empties the sheet, so this message is then where
  /// focus rests. A search that finds nothing says so; without a search or
  /// the filter it never reads as one.
  Widget _noBoards(BuildContext context) {
    final searched = jump.text.trim().isNotEmpty;
    if (missingOnly && (!searched || allEntered)) {
      final colors = Theme.of(context).colorScheme;
      return Focus(
        focusNode: doneNode,
        onFocusChange: (_) => setState(() {}),
        child: Semantics(
          liveRegion: true,
          child: Container(
            key: const ValueKey('all-results-entered'),
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: doneNode.hasFocus
                    ? focusRing(colors)
                    : Colors.transparent,
                width: focusRingWidth,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: EmptyState(
              icon: Icons.check_circle_outline,
              title: searched
                  ? 'All matching boards entered'
                  : 'All results entered',
              body: searched
                  ? 'Clear the search or turn off Missing only to see the other boards.'
                  : 'Turn off Missing only to review them.',
            ),
          ),
        ),
      );
    }
    return searched
        ? const EmptyState(
            icon: Icons.search_off,
            title: 'No matching boards',
            body: 'Try another name or board number.',
          )
        : const EmptyState(
            icon: Icons.grid_view_outlined,
            title: 'No boards in this round',
            body: 'Nobody is paired against an opponent in this round.',
          );
  }

  /// Before there is anything to pair: what to do next, with the way
  /// there when the workspace gave one.
  Widget _nothingToPair(BuildContext context) {
    // No boards: a jump must not use positions from the last sheet drawn.
    _itemOf = const {};
    _itemCount = 0;
    final noPlayers = c.event!.players.isEmpty;
    final action = noPlayers ? widget.onAddPlayers : widget.onNewSection;
    return EmptyState(
      key: const ValueKey('nothing-to-pair'),
      icon: noPlayers ? Icons.group_add_outlined : Icons.table_rows_outlined,
      title: noPlayers ? 'No players yet' : 'No section yet',
      body: noPlayers
          ? sections.isEmpty
                ? 'Add players on the Players page, then create a section to pair them.'
                : 'Add players on the Players page to pair them here.'
          : 'Create a section to pair these players.',
      action: action == null
          ? null
          : OutlinedButton(
              key: ValueKey(
                noPlayers ? 'empty-add-players' : 'empty-new-section',
              ),
              onPressed: action,
              child: Text(noPlayers ? 'Add players' : 'New section'),
            ),
    );
  }

  /// A withdrawn player still sitting at a board that has not started:
  /// said above the boards, with the way to pair those boards again.
  Widget? _withdrawnNotice(BuildContext context, Round round) {
    final e = c.event!, waiting = unstartedBoards(round).toSet();
    final gone = [
      for (final g in round.games.where((g) => waiting.contains(g.board)))
        if (g.leg == 1)
          for (final id in [g.white, g.black])
            if (e.player(id).withdrawn) (e.player(id).name, g.board),
    ];
    if (gone.isEmpty) return null;
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('repair-notice'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(
            Icons.person_off_outlined,
            size: 18,
            color: colors.onSecondaryContainer,
          ),
          Text(
            gone.length == 1
                ? '${gone.single.$1} withdrew but is still on board ${gone.single.$2}.'
                : '${gone.length} withdrawn players are still on boards that have not started.',
            style: TextStyle(color: colors.onSecondaryContainer),
          ),
          OutlinedButton(
            key: const ValueKey('repair-notice-action'),
            onPressed: repairing ? null : () => openRepair(round),
            child: const Text('Re-pair unstarted boards'),
          ),
        ],
      ),
    );
  }

  /// Under the boards: whose result the focused box enters, and the keys.
  /// A key that is not a result makes the legend say so.
  Widget _legend(BuildContext context, List<BoardRow> visible) {
    final colors = Theme.of(context).colorScheme, e = c.event!;
    final focused = boxes[activeBox]?.hasFocus == true;
    final row = !focused
        ? null
        : visible
              .where(
                (r) =>
                    activeBox == '${r.game.id}-w' ||
                    activeBox == '${r.game.id}-b',
              )
              .firstOrNull;
    final white = activeBox?.endsWith('-w') ?? true;
    final line = row == null
        ? null
        : [
            if (widget.sectionId == null) row.section.name,
            'Round ${row.round.number}',
            'Board ${row.game.board}${row.section.doubleGames ? ' · Game ${row.game.leg}' : ''}',
            '${e.player(row.game.white).name} vs ${e.player(row.game.black).name}',
            locked(row)
                ? 'read-only'
                : 'entering ${white ? 'White' : 'Black'}\'s result',
          ].join(' · ');
    return Container(
      key: const ValueKey('result-legend'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The status line is always there, two lines tall, so the sheet
          // keeps its height as the cursor comes and goes and when the
          // last result is entered. A long context line wraps onto the
          // second line rather than losing whose result is being entered.
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.textScalerOf(context).scale(_statusLine),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              heightFactor: 1,
              child: allEntered
                  ? _allEntered(context)
                  : line == null
                  ? const SizedBox.shrink()
                  : Text(
                      line,
                      key: const ValueKey('entry-context'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
            ),
          ),
          Semantics(
            liveRegion: invalidKey,
            child: Text(
              invalidKey && forfeitRefused
                  ? 'A forfeit is only won or lost. 1 or 0 picks who won it · Delete clears it to enter a played game'
                  : invalidKey && drawHint
                  ? '$drawKeyHint · $resultKeyHint'
                  : invalidKey
                  ? 'Not a result key. $resultKeyHint · $moreResultKeys'
                  : row != null && !locked(row) && isForfeit(row.game.outcome)
                  ? '${forfeitKeyHint(row.game.outcome, white: white)} · $gridKeyHint'
                  : '$resultKeyHint · $gridKeyHint',
              key: const ValueKey('result-key-legend'),
              style: TextStyle(
                fontSize: 12,
                color: invalidKey ? colors.onSurface : colors.onSurfaceVariant,
                fontWeight: invalidKey ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What is read-only among the rounds on screen, in words: all of it, or
  /// only the earlier Swiss rounds, named so the boards beside them are
  /// not taken for locked too.
  String readOnlyText(List<(Section, Round)> shown) {
    final locked = [
      for (final (s, r) in shown)
        if (earlier(s, r)) (s, r),
    ];
    if (locked.length == shown.length) return 'Read-only';
    if (locked.length == 1) {
      final (s, r) = locked.single;
      return widget.sectionId == null
          ? '${s.name} round ${r.number} is read-only'
          : 'Round ${r.number} is read-only';
    }
    return showAllRounds
        ? 'Earlier rounds are read-only'
        : '${locked.length} sections are read-only';
  }

  /// Shown while an earlier round is on screen, so nobody enters this
  /// round's results there by mistake. Typing into a locked box says how.
  Widget _pastStatus(BuildContext context, List<(Section, Round)> shown) {
    final colors = Theme.of(context).colorScheme;
    final color = correcting ? colors.error : colors.onSurfaceVariant;
    final what = readOnlyText(shown);
    return Row(
      key: const ValueKey('past-round-banner'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          correcting ? Icons.edit_outlined : Icons.lock_outline,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            correcting
                ? 'Correcting · review each change before saving'
                : nudged
                ? '$what · choose Correct a result to change it'
                : what,
            style: TextStyle(
              fontSize: 14,
              color: nudged && !correcting ? colors.onSurface : color,
              fontWeight: nudged && !correcting ? FontWeight.w600 : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _swapBanner(BuildContext context, Round r) {
    final colors = Theme.of(context).colorScheme;
    final picked = swapPick == null ? null : c.event!.player(swapPick!);
    return Container(
      key: const ValueKey('swap-banner'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.swap_horiz, size: 18, color: colors.onSecondaryContainer),
          const SizedBox(width: 8),
          Text(
            picked == null
                ? 'Click two players to swap them. Two on one board swap colours.'
                : 'Swap ${picked.name} with… click another player, or click ${picked.name} again to cancel.',
            style: TextStyle(color: colors.onSecondaryContainer),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
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

  /// A quad round that posting would refuse is not shown; say why.
  Widget _scheduleIssue(BuildContext context, Section s, String issue) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey(('quad-schedule-issue', s.id)),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        widget.sectionId == null ? '${s.name}: $issue' : issue,
        style: TextStyle(color: colors.onErrorContainer),
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
    final e = c.event!;
    final bySection = <(String, int), List<BoardRow>>{};
    for (final r in visible) {
      bySection.putIfAbsent((r.section.id, r.round.number), () => []).add(r);
    }
    int firstBoard((Section, Round) x) =>
        x.$2.games.map((g) => g.board).fold(1 << 30, math.min);
    final ordered = [...shown]
      ..sort((a, b) {
        final round = a.$2.number.compareTo(b.$2.number);
        return round != 0 ? round : firstBoard(a).compareTo(firstBoard(b));
      });
    // Builders, not rows: the list makes only the rows on screen.
    final items = <WidgetBuilder>[];
    final itemOf = <String, int>{};
    for (final (s, r) in ordered) {
      final boards = bySection[(s.id, r.number)] ?? const <BoardRow>[];
      final byes = missingOnly
          ? const <ByeAward>[]
          : r.byes.where((b) => named(e.player(b.player))).toList();
      if (boards.isEmpty && byes.isEmpty) continue;
      if (widget.sectionId == null || allRoundsOf(s)) {
        items.add((context) => _sectionRow(context, s, r));
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
          final points = last = group(row.game);
          items.add((context) => _scoreGroup(context, points));
        }
        itemOf[row.game.id] = items.length;
        items.add((context) => _game(context, row, before));
      }
      for (final b in byes) {
        items.add(
          (context) => _bye(context, b, r.number, every: allRoundsOf(s)),
        );
      }
    }
    _itemOf = itemOf;
    _itemCount = items.length;
    return _frame(context, items, footer: _legend(context, visible));
  }

  /// The ruled sheet the boards sit on, with a column header that stays put
  /// while the boards scroll under it.
  Widget _frame(
    BuildContext context,
    List<WidgetBuilder> items, {
    Widget? footer,
  }) {
    final colors = Theme.of(context).colorScheme;
    // The sheet built in full, for the layouts that are not lazy.
    List<Widget> whole(BuildContext context) => [
      _columns(context),
      for (final item in items) item(context),
      ?footer,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep player names and inline actions readable at enlarged text sizes.
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final width = constraints.maxWidth.clamp(
          520 * scale,
          _widestPane * scale,
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLowest,
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: !constraints.hasBoundedHeight
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: whole(context),
                      )
                    : constraints.maxHeight <
                          MediaQuery.textScalerOf(context).scale(150)
                    ? SingleChildScrollView(
                        controller: scroll,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: whole(context),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _columns(context),
                          // Lazy: a round of hundreds of boards builds only
                          // those on screen, so entering a result stays quick.
                          // Shrink-wrapped so a short round's sheet ends at
                          // its last board; it still lays out only what shows.
                          Flexible(
                            child: ListView.builder(
                              controller: scroll,
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: items.length,
                              itemBuilder: (context, i) => items[i](context),
                            ),
                          ),
                          ?footer,
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  static const _board = 40.0, _row = 32.0, _statusLine = 38.0;

  /// The widest a pane of boards grows, before text scaling.
  static const _widestPane = 760.0;
  double scoreWidth(BuildContext context) =>
      math.max(36, MediaQuery.textScalerOf(context).scale(32));

  /// The board column grows with the text, so its "Board" heading still fits
  /// at large text sizes (it vanished at 200%; found by the UI fuzzer).
  double boardWidth(BuildContext context) =>
      math.max(_board, MediaQuery.textScalerOf(context).scale(_board));

  /// Before round 1: the board sheet with nothing filled in, one row per
  /// board the section will need, so nothing moves when pairings arrive.
  Widget _blankTable(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final e = c.event!;
    final muted = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: colors.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget box() => Container(
      width: scoreWidth(context),
      height: 24,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
    );
    Widget row(String label, {bool bye = false}) => Container(
      constraints: const BoxConstraints(minHeight: _row),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: boardWidth(context),
            child: Text(label, style: muted),
          ),
          if (bye) SizedBox(width: scoreWidth(context)) else box(),
          const Spacer(),
          if (!bye) box(),
        ],
      ),
    );
    final items = <Widget>[];
    for (final s in sections) {
      final entrants = s.players.where((id) => !e.player(id).withdrawn).length;
      if (widget.sectionId == null) {
        items.add(
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.outlineVariant),
                bottom: BorderSide(color: colors.outlineVariant),
              ),
            ),
            child: Text(
              s.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }
      for (var board = 1; board <= entrants ~/ 2; board++) {
        items.add(row('$board'));
      }
      if (entrants.isOdd) items.add(row('Bye', bye: true));
    }
    // No boards: a jump must not use positions from the last sheet drawn.
    _itemOf = const {};
    _itemCount = 0;
    return KeyedSubtree(
      key: const ValueKey('blank-board-sheet'),
      child: Semantics(
        label: 'Boards appear here when pairings are created.',
        child: _frame(context, [for (final item in items) (_) => item]),
      ),
    );
  }

  Widget _columns(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('board-column-header'),
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DefaultTextStyle.merge(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
        child: Row(
          children: [
            SizedBox(width: boardWidth(context), child: const Text('Board')),
            SizedBox(
              width: scoreWidth(context),
              child: Text('Score', textAlign: TextAlign.center),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('White')),
            SizedBox(width: 12),
            Expanded(child: Text('Black', textAlign: TextAlign.right)),
            SizedBox(width: 12),
            SizedBox(
              width: scoreWidth(context),
              child: Text('Score', textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }

  /// Section name above its boards when every section is on screen.
  Widget _sectionRow(BuildContext context, Section s, Round r) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('board-round-heading-${s.id}-${r.number}'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant),
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Text(
        allRoundsOf(s) ? '${s.name} · Round ${r.number}' : s.name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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

  /// A bye, listed after the boards.
  Widget _bye(
    BuildContext context,
    ByeAward b,
    int round, {
    required bool every,
  }) {
    final colors = Theme.of(context).colorScheme;
    final p = c.event!.player(b.player);
    return Container(
      key: ValueKey(every ? 'bye-${p.id}-$round' : 'bye-${p.id}'),
      constraints: const BoxConstraints(minHeight: _row),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: boardWidth(context),
            child: Text(
              'Bye',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: scoreWidth(context),
            child: Text(
              halves(b.points),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                    // The grid is one Tab stop; names are not.
                    child: ExcludeFocusTraversal(
                      child: InkWell(
                        key: ValueKey(
                          every
                              ? 'bye-player-${p.id}-$round'
                              : 'bye-player-${p.id}',
                        ),
                        onTap: () => showPlayer(p.id),
                        child: Text(
                          p.name,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  // The points are in the score column; a pairing bye needs
                  // no further words.
                  if (!b.allocated)
                    TextSpan(
                      text: '   ${b.reason.toLowerCase()}',
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
            // A bughouse side is both partners: "Chen / Patel".
            TextSpan(
              text: switch (p.id == g.white ? g.whitePartner : g.blackPartner) {
                '' => p.name,
                final partner => '${p.name} / ${e.player(partner).name}',
              },
            ),
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
        style: const TextStyle(fontSize: 14),
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
      void menu(Offset at) => showPlayerMenu(
        context,
        c,
        p.id,
        at,
        onByes: (id) => showPlayer(id, focus: 'byes'),
      );
      // The grid is one Tab stop, so names are not: Space on a score box
      // opens that player's details, Shift+F10 their menu.
      final playerLink = ExcludeFocusTraversal(
        child: Tooltip(
          message: '${p.name} · Double-click for player details',
          child: ContextMenuKeys(
            onMenu: menu,
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
                  onSecondaryTapDown: (details) => menu(details.globalPosition),
                  onDoubleTap: () => showPlayer(p.id),
                  child: label,
                ),
              ),
            ),
          ),
        ),
      );
      final forfeited =
          g.outcome == Outcome.doubleForfeit ||
          (p.id == g.white && g.outcome == Outcome.blackForfeit) ||
          (p.id == g.black && g.outcome == Outcome.whiteForfeit);
      if (!forfeited || past(row)) return playerLink;
      return Column(
        crossAxisAlignment: right
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          playerLink,
          if (p.withdrawn)
            Text(
              'Withdrawn',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            )
          else
            // Reached with Tab only from this board's score boxes.
            ExcludeFocusTraversal(
              excluding: !{'${g.id}-w', '${g.id}-b'}.contains(entryBox),
              child: TextButton(
                key: ValueKey('withdraw-${g.id}-${p.id}'),
                onPressed: () {
                  try {
                    c.setWithdrawn([p.id], true);
                  } catch (error) {
                    if (mounted) showFailure(context, error);
                  }
                },
                // The same words as the player menu and the player card.
                child: Text(statusLabel(e, StatusAction.withdraw, [p.id])),
              ),
            ),
        ],
      );
    }

    return GestureDetector(
      key: ValueKey('game-${g.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => focusBox(g.id, true),
      child: Container(
        constraints: const BoxConstraints(minHeight: _row),
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
              'Round ${row.round.number}, board ${g.board}, ${white.name} versus ${black.name}: ${g.outcome.label}${lock ? ', read-only' : ''}',
          child: Row(
            children: [
              SizedBox(
                width: boardWidth(context),
                child: Text(
                  '${g.board}${row.section.doubleGames ? '·${g.leg}' : ''}',
                  style: TextStyle(
                    fontSize: 14,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreBox(BuildContext context, BoardRow row, {required bool white}) {
    final colors = Theme.of(context).colorScheme, g = row.game;
    final node = box(g.id, white), lock = locked(row);
    node.skipTraversal = '${g.id}-${white ? 'w' : 'b'}' != entryBox;
    final owner = c.event!.player(white ? g.white : g.black);
    final assumed = !g.outcome.resolved && g.pairingAssumption != null;
    // Unfinished, disputed and assumed results each look different from an
    // empty box, so none of them reads as "not reported yet".
    final (mark, caption) = switch (g.outcome) {
      // A game still going may carry an assumption for pairing.
      Outcome.unfinished when assumed => (
        '(${scoreMark(g.pairingAssumption!, white: white)})',
        'playing',
      ),
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
      Outcome.unfinished when assumed =>
        'still playing, assumed ${mark.replaceAll(RegExp('[()]'), '')} for pairing only',
      Outcome.unfinished => 'still playing',
      Outcome.disputed => 'disputed',
      Outcome.doubleForfeit => 'double forfeit',
      _ when !g.outcome.played => mark == 'X' ? 'won by forfeit' : 'forfeited',
      _ => mark,
    };
    return ContextMenuKeys(
      onMenu: (at) => showPlayerMenu(
        context,
        c,
        owner.id,
        at,
        onByes: (id) => showPlayer(id, focus: 'byes'),
      ),
      child: Focus(
        focusNode: node,
        onKeyEvent: (_, event) => onKey(row, white, event),
        onFocusChange: (has) {
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
                  width: scoreWidth(context),
                  constraints: const BoxConstraints(minHeight: 24),
                  padding: EdgeInsets.symmetric(
                    vertical: caption == null ? 3 : 2,
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1,
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
      ),
    );
  }
}

/// Pairs again the boards of a section's latest round that have not
/// started, as after a player withdrew once pairings were posted (rule
/// 29G3). Docked beside the boards. A board with a result or a pairing
/// assumption is kept as it is, and so is any board the director ticks
/// here as already started; the rest are paired again without withdrawn
/// players. Afterwards the panel says what changed, with Undo.
class RepairPanel extends StatefulWidget {
  const RepairPanel({
    required this.controller,
    required this.sectionId,
    required this.reason,
    required this.started,
    required this.onClose,
    super.key,
  });
  final TournamentController controller;
  final String sectionId;

  /// Why the posted pairing is changing. Owned by the view, like
  /// [started], so closing the panel keeps what was entered.
  final TextEditingController reason;

  /// Boards without a result that the director says have started.
  final Set<int> started;
  final VoidCallback onClose;
  @override
  State<RepairPanel> createState() => _RepairPanelState();
}

class _RepairPanelState extends State<RepairPanel> {
  TournamentController get c => widget.controller;
  String? error;

  /// What was re-paired, so the panel can confirm it and offer Undo.
  ({
    int round,
    int boards,
    int kept,
    List<String> byes,
    List<String> notes,
    String reason,
    int head,
  })?
  saved;

  @override
  void initState() {
    super.initState();
    widget.reason.addListener(changed);
    c.addListener(changed);
  }

  @override
  void dispose() {
    widget.reason.removeListener(changed);
    c.removeListener(changed);
    super.dispose();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Round? get round => c.event?.sections
      .where((s) => s.id == widget.sectionId)
      .firstOrNull
      ?.rounds
      .lastOrNull;

  void apply(Round round, List<int> redo) {
    final e = c.event!;
    final boards = round.games.map((g) => g.board).toSet();
    final hadBye = {for (final b in round.byes) b.player};
    final reason = widget.reason.text.trim();
    try {
      final notes = c.repairUnstarted(widget.sectionId, [
        for (final g in round.games)
          if (!redo.contains(g.board)) g.id,
      ], reason);
      final now = this.round!;
      setState(() {
        saved = (
          round: round.number,
          boards: redo.length,
          kept: boards.length - redo.length,
          byes: [
            for (final b in now.byes)
              if (!hadBye.contains(b.player) && !e.player(b.player).withdrawn)
                '${e.player(b.player).name} now has a bye (${pointsText(b.points)}).',
          ],
          notes: notes,
          reason: reason,
          head: c.graph.head!,
        );
        error = null;
      });
      widget.started.clear();
      widget.reason.clear();
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  void undoSaved() {
    final done = saved;
    if (done == null || c.graph.head != done.head) return;
    try {
      c.undo();
      setState(() => saved = null);
      widget.reason.text = done.reason;
    } catch (e) {
      setState(() => error = plainMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (saved != null) return _savedState(context);
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    final e = c.event!, r = round;
    final open = r == null ? const <int>[] : unstartedBoards(r);
    if (r == null || open.isEmpty) {
      return SidePanel(
        title: 'Re-pair unstarted boards',
        onClose: widget.onClose,
        children: const [
          Text(
            'Every board of this round has a result or has started, so there is nothing to pair again.',
          ),
        ],
      );
    }
    bool withdrawn(int board) => r.games.any(
      (g) =>
          g.board == board &&
          (e.player(g.white).withdrawn || e.player(g.black).withdrawn),
    );
    // A board with a withdrawn player cannot be kept waiting.
    final redo = [
      for (final b in open)
        if (!widget.started.contains(b) || withdrawn(b)) b,
    ];
    final why = redo.isEmpty
        ? 'Every board is kept, so there is nothing to pair again.'
        : widget.reason.text.trim().isEmpty
        ? 'Say why the pairings are changing.'
        : null;
    void commit() {
      if (why == null) apply(r, redo);
    }

    final count = redo.length == 1 ? '1 board' : '${redo.length} boards';
    return KeyedSubtree(
      key: const ValueKey('repair-panel'),
      child: SidePanel(
        title: 'Re-pair unstarted boards',
        onClose: widget.onClose,
        footer: [
          if (error != null)
            Row(
              key: const ValueKey('repair-error'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 20, color: colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(error!, style: TextStyle(color: colors.error)),
                ),
              ],
            )
          else if (why != null)
            Text(why, style: muted),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('apply-repair'),
            onPressed: why == null ? commit : null,
            child: Text('Re-pair $count'),
          ),
        ],
        children: [
          Text('Round ${r.number}', style: muted),
          const SizedBox(height: 4),
          Text(
            key: const ValueKey('repair-summary'),
            'Boards with a result or already started are kept. '
            '${redo.length == 1 ? 'The 1 board not started is' : 'The ${redo.length} boards not started are'} '
            'paired again, without withdrawn players.'
            '${r.byes.any((b) => b.allocated) ? ' The player with the bye joins them, so the bye may change.' : ''}',
          ),
          const SizedBox(height: 16),
          Text(
            'Boards without a result',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Tick any that have already started. They are kept.',
            style: muted,
          ),
          const SizedBox(height: 8),
          for (final b in open)
            _waitingBoard(context, r, b, withdrawn: withdrawn(b)),
          const SizedBox(height: 16),
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): commit,
              const SingleActivator(LogicalKeyboardKey.numpadEnter): commit,
            },
            child: TextField(
              key: const ValueKey('repair-reason'),
              controller: widget.reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                helperText: 'Printed with this round\'s pairings',
              ),
              minLines: 1,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  /// One board without a result: who is on it, and whether it has started.
  Widget _waitingBoard(
    BuildContext context,
    Round r,
    int board, {
    required bool withdrawn,
  }) {
    final e = c.event!, colors = Theme.of(context).colorScheme;
    final g = r.games.firstWhere((g) => g.board == board);
    final white = e.player(g.white), black = e.player(g.black);
    final gone = [
      for (final p in [white, black])
        if (p.withdrawn) p.name,
    ];
    final ticked = !withdrawn && widget.started.contains(board);
    void toggle(bool on) => setState(
      () => on ? widget.started.add(board) : widget.started.remove(board),
    );
    return InkWell(
      onTap: withdrawn ? null : () => toggle(!ticked),
      canRequestFocus: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlainCheckbox(
              key: ValueKey('repair-started-$board'),
              value: ticked,
              label: 'Board $board has started',
              onChanged: withdrawn ? null : (v) => toggle(v ?? false),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Board $board · ${white.name} – ${black.name}'),
                    if (gone.isNotEmpty)
                      Text(
                        '${gone.join(' and ')} withdrew, so this board is paired again.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      )
                    else if (ticked)
                      Text(
                        'Started: kept as it is.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _savedState(BuildContext context) {
    final done = saved!, colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    // The decisions a director checks come first; routine notes follow.
    final review = [
      for (final line in done.notes)
        if (PairingReview.of(line) != null) line,
    ];
    final routine = [
      for (final line in done.notes)
        if (PairingReview.of(line) == null) line,
    ];
    const most = 8;
    return KeyedSubtree(
      key: const ValueKey('repair-saved'),
      child: SidePanel(
        title: 'Round ${done.round} re-paired',
        onClose: widget.onClose,
        footer: [
          if (error != null) ...[
            Text(error!, style: TextStyle(color: colors.error)),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              if (c.graph.head == done.head)
                OutlinedButton.icon(
                  key: const ValueKey('repair-undo'),
                  onPressed: undoSaved,
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo'),
                ),
              const Spacer(),
              OutlinedButton(
                key: const ValueKey('repair-done'),
                onPressed: widget.onClose,
                child: const Text('Done'),
              ),
            ],
          ),
        ],
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 20,
                color: colors.onSurface,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${done.boards == 1 ? '1 board was' : '${done.boards} boards were'} paired again; '
                  '${done.kept == 1 ? '1 board was' : '${done.kept} boards were'} kept.',
                ),
              ),
            ],
          ),
          for (final line in [...done.byes, ...review]) ...[
            const SizedBox(height: 8),
            Text(line),
          ],
          const SizedBox(height: 12),
          Text(
            'Reprint the pairings and result sheets for this round. Copies already posted show the old boards.',
            style: muted,
          ),
          if (routine.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Pairing notes',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final line in routine.take(most)) ...[
              const SizedBox(height: 4),
              Text(line, style: muted),
            ],
            if (routine.length > most) ...[
              const SizedBox(height: 4),
              Text('And ${routine.length - most} more.', style: muted),
            ],
          ],
        ],
      ),
    );
  }
}
