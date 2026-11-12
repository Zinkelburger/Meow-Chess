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
import 'results_view_model.dart';
import 'theme.dart';
import 'workspace_status.dart';

export 'results_view_model.dart' show BoardRow, unstartedBoards;

part 'results_view_widgets.dart';

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

  /// Which rounds are on screen, and whether an earlier one is being
  /// corrected.
  final selection = RoundSelection();

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
    selection.showAllRounds = allQuads;
    roundSignature = signature();
    final saved = c.workspaceState.readMap(preference);
    if (c.workspaceState.read('pairings-missing-only') == null) {
      c.workspaceState.write(
        'pairings-missing-only',
        '${saved['missingOnly'] == true}',
      );
    }
    final restored = SavedResultsView.restore(saved, roundSignature);
    if (restored != null) {
      selection
        ..selectedRound = restored.round
        ..showAllRounds = restored.allRounds
        ..scheduleRounds = restored.scheduleRounds;
      jump.text = restored.search;
      activeBox = restored.box;
      scrollOffset = restored.scroll;
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
      if (scroll.hasClients && restored != null) {
        scroll.jumpTo(
          restored.scroll.clamp(0, scroll.position.maxScrollExtent),
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
    roundNumber: sections.every(hasFixedQuadSchedule)
        ? null
        : selection.selectedRound,
    kind: ReportKind.packet,
  );

  Iterable<Section> get sections => c.pairingEvent.sections.where(
    (s) => widget.sectionId == null || s.id == widget.sectionId,
  );

  bool get allQuads =>
      sections.isNotEmpty && sections.every(hasFixedQuadSchedule);

  String signature() => roundCountSignature(sections);

  @override
  void didUpdateWidget(covariant ResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = signature();
    // A round was posted or undone: go back to the current round.
    if (roundSignature.isNotEmpty && next != roundSignature) {
      selection.reset(allQuads: allQuads);
      allEntered = invalidKey = false;
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
      boxes.putIfAbsent(boxKey(gameId, white), () {
        final node = FocusNode(
          debugLabel: 'score $gameId ${white ? 'white' : 'black'}',
        );
        node.addListener(() {
          if (node.hasFocus) {
            activeBox = boxKey(gameId, white);
            invalidKey = false;
            // Back on a board: the status line names it again.
            allEntered = false;
            remember();
          }
        });
        return node;
      });

  List<BoardRow> rows() => boardRows(sections, selection);

  List<BoardRow> visibleRows() => filterBoardRows(
    rows(),
    c.event!,
    query: jump.text,
    missingOnly: missingOnly,
  );

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
    final state = SavedResultsView(
      signature: roundSignature,
      round: selection.selectedRound,
      allRounds: selection.showAllRounds,
      scheduleRounds: selection.scheduleRounds,
      search: jump.text,
      box: activeBox,
      scroll: scroll.hasClients ? scroll.offset : scrollOffset,
    ).toMap();
    final next = '$state';
    if (next == remembered) return;
    if (c.workspaceState.writeMap(preference, state)) remembered = next;
  }

  /// The rows last drawn (section headings, score groups and byes
  /// included) and where each board sits among them. Empty whenever no
  /// boards are drawn, so a jump never uses positions from an older sheet.
  SheetLayout _sheet = SheetLayout.empty;

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
          if (_sheet.itemOf[gameId] case final index?) {
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
    for (final MapEntry(key: id, value: index) in _sheet.itemOf.entries) {
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
      offset = total * target / math.max(1, _sheet.items.length) - lead;
    }
    return offset.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  /// Puts the cursor in White's box on the first board without a result.
  void focusFirst() {
    if (!mounted) return;
    final row = firstOpenRow(visibleRows());
    if (row != null) focusBox(row.game.id, true);
  }

  /// Moves [by] boards up or down, keeping the same side.
  void step(String gameId, bool white, int by) {
    final next = stepFrom(visibleRows(), gameId, by);
    if (next != null) focusBox(next, white);
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
    final next = nextOpenGame(ids, rows(), gameId);
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
    if (selection.locked(row)) {
      setState(() => selection.nudged = true);
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

  /// What replacing the result of [row] did, for the notice with Undo.
  String overwriteNotice(BoardRow row, Outcome before, Outcome now) =>
      overwriteNoticeText(
        row,
        before,
        now,
        everySection: widget.sectionId == null,
        allRounds: selection.allRoundsOf(row.section),
      );

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
    setState(() => selection.pick(n, latest));
    WidgetsBinding.instance.addPostFrameCallback((_) => focusFirst());
  }

  /// What the grid makes of [event] on a box for White ([white]) or Black,
  /// on a board whose result is [current].
  static GridKeyPress _gridKeyPress(
    KeyEvent event, {
    required bool white,
    required Outcome current,
  }) => GridKeyPress(
    // By position on a keyboard layout without Latin letters.
    switch (commandKey(event)) {
      LogicalKeyboardKey.arrowUp => GridKey.up,
      LogicalKeyboardKey.arrowDown => GridKey.down,
      LogicalKeyboardKey.arrowLeft => GridKey.left,
      LogicalKeyboardKey.arrowRight => GridKey.right,
      LogicalKeyboardKey.enter ||
      LogicalKeyboardKey.numpadEnter => GridKey.enter,
      LogicalKeyboardKey.keyA => GridKey.assume,
      LogicalKeyboardKey.space => GridKey.details,
      LogicalKeyboardKey.f2 => GridKey.correct,
      LogicalKeyboardKey.delete ||
      LogicalKeyboardKey.backspace => GridKey.clear,
      _ => GridKey.other,
    },
    release: event is KeyUpEvent,
    repeat: event is KeyRepeatEvent,
    modified:
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed,
    shift: HardwareKeyboard.instance.isShiftPressed,
    outcome: resultFromKey(event, white: white, current: current),
    drawAttempt: isDrawAttempt(event),
    printable: (event.character ?? '').trim().isNotEmpty,
    refusedOnForfeit: refusedOnForfeit(event, current),
  );

  KeyEventResult onKey(BoardRow row, bool white, KeyEvent event) {
    final g = row.game;
    final action = gridKeyAction(
      _gridKeyPress(event, white: white, current: g.outcome),
      busy: busy,
      locked: selection.locked(row),
      current: g.outcome,
    );
    switch (action) {
      case GridKeyIgnored():
        return KeyEventResult.ignored;
      case GridKeySwallowed():
        break;
      case GridMoveBoard(:final by):
        step(g.id, white, by);
      case GridMoveSide(white: final toWhite):
        focusBox(g.id, toWhite);
      case GridAssume():
        assume(g.id);
      case GridShowPlayer():
        showPlayer(white ? g.white : g.black);
      case GridCorrect():
        // The review opens beside the table.
        openResultCorrection(
          context,
          c,
          g.id,
          white: white,
          onDone: () {
            if (mounted) focusBox(g.id, white);
          },
        );
      case GridRefuse(:final forfeit, :final draw):
        setState(() {
          invalidKey = true;
          forfeitRefused = forfeit;
          drawHint = draw;
        });
      case GridEnter(:final outcome, :final clearsHint):
        if (clearsHint && invalidKey) setState(() => invalidKey = false);
        enter(row, outcome, white: white);
    }
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

  /// Opens re-pairing beside the boards. The reason starts as the
  /// withdrawal that usually prompts it, for the director to change.
  void openRepair(Round round) {
    if (!applyCardEdits()) return;
    if (repairReason.text.trim().isEmpty) {
      if (suggestedRepairReason(round, c.event!) case final reason?) {
        repairReason.text = reason;
      }
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

  void closeAssume() {
    Dock.maybeOf(context)?.close();
    setState(() => assumeFor = null);
  }

  /// First click picks a player; the second swaps the two, saved as a new
  /// pairing revision. Two players on one board swap colours.
  void pickSwap(String id) {
    final next = pickForSwap(swapPick, id);
    setState(() => swapPick = next.pick);
    final a = next.swapWith;
    if (a == null) return;
    final s = sections.single, r = s.rounds.last, e = c.event!;
    try {
      c.replacePairing(
        s.id,
        r.number,
        swapInRound(r, a, id),
        'Swapped ${e.player(a).name} and ${e.player(id).name}',
      );
    } catch (error) {
      showFailure(context, error);
    }
  }

  void withdraw(String id) {
    try {
      c.setWithdrawn([id], true);
    } catch (error) {
      if (mounted) showFailure(context, error);
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
    selection.keepWithin(roundNumbers);
    final shown = [
      for (final s in sections)
        for (final r in selection.shownRounds(s)) (s, r),
    ];
    final all = rows(), visible = visibleRows();
    // Tab enters the grid at the active box, or the first board missing a
    // result; every other box is reached with the arrows.
    entryBox = entryBoxFor(visible, activeBox);
    // Any earlier Swiss round on screen: its boards are read-only, while
    // other sections' boards beside it stay open for entry.
    final viewingPast = shown.any((x) => isEarlierRound(x.$1, x.$2));
    final player = e.players.where((p) => p.id == openPlayerId).firstOrNull;
    if (assumeFor != null && !all.any((r) => r.game.id == assumeFor)) {
      assumeFor = null;
    }
    final everySection = widget.sectionId == null;
    final repair = repairableRound(shown, singleSection: !everySection);
    if (repair == null) repairing = false;
    final single = everySection ? null : shown.singleOrNull;
    if (viewingPast || single == null || single.$2.hasPlay) {
      swapping = false;
      swapPick = null;
    }
    final heading = roundHeading(
      shown,
      sections,
      all,
      showAllRounds: selection.showAllRounds,
    );
    final boardHeading = _RoundLine(
      title: heading.title,
      facts: heading.facts,
      // An earlier round says so in words beside its title; the way in
      // (Correct a result) and out (Done correcting) is in the toolbar.
      pastStatus: viewingPast
          ? _PastStatus(
              correcting: selection.correcting,
              nudged: selection.nudged,
              what: readOnlyText(
                shown,
                everySection: everySection,
                showAllRounds: selection.showAllRounds,
              ),
            )
          : null,
      // Bughouse pairs partnerships: form them here before round 1.
      partners: heading.numbers.isEmpty
          ? sections
                .where((s) => s.format == Format.bughouse && s.rounds.isEmpty)
                .firstOrNull
          : null,
      onPartners: (s) => showBughousePartners(context, c, sectionId: s.id),
      roundNumbers: roundNumbers,
      selectedRound: selection.selectedRound,
      showAllRounds: selection.showAllRounds,
      onPickRound: (n) => pickRound(n, roundNumbers.last),
      onShowAll: () => setState(selection.showAll),
    );
    // Always present, so the boards start at the same height in every
    // section whether or not it has pairings yet.
    final quad = sections.where(hasFixedQuadSchedule).singleOrNull;
    final editable = !viewingPast && single != null && !single.$2.hasPlay;
    final boardToolbar = _BoardToolbar(
      controller: c,
      search: jump,
      searchable: shown.isNotEmpty,
      onSearchChanged: () => setState(() {}),
      onSearchSubmitted: () {
        final first = visibleRows().firstOrNull;
        if (first != null) focusBox(first.game.id, true);
      },
      // A finished Holland prelim offers its final from here.
      prelim: sections
          .where((s) => s.id == widget.sectionId && isHollandPrelim(s))
          .firstOrNull,
      viewingPast: viewingPast,
      correcting: selection.correcting,
      onCorrect: () => setState(selection.startCorrecting),
      onDoneCorrecting: () => setState(selection.stopCorrecting),
      onEditPairings: (quad != null || editable) && !swapping
          ? quad != null
                ? () => showQuadPairingsEditor(context, c, sectionId: quad.id)
                : () => setState(() {
                    swapping = true;
                    swapPick = null;
                  })
          : null,
      repair: repair,
      onRepair: repair == null ? null : () => openRepair(repair.round),
      missingOnly: missingOnly,
      onMissingOnly: shown.isEmpty
          ? null
          : (v) => setState(
              () => c.workspaceState.write('pairings-missing-only', '$v'),
            ),
      printTooltip: sections.every(hasFixedQuadSchedule)
          ? 'Print pairings and result sheets'
          : selection.showAllRounds
          ? 'Print pairings and result sheets for the current round'
          : 'Print pairings and result sheets for this round',
      onPrint: shown.isEmpty ? null : printRound,
    );
    // Notices belong to the boards, so they sit in the boards pane and never
    // push the crosstable beside it down.
    final notices = [
      for (final s in sections)
        if (c.quadScheduleIssues[s.id] case final issue?)
          _ScheduleIssue(
            sectionId: s.id,
            text: everySection ? '${s.name}: $issue' : issue,
          ),
      if (swapping)
        _SwapBanner(
          picked: swapPick == null ? null : e.player(swapPick!).name,
          onDone: () => setState(() {
            swapping = false;
            swapPick = null;
          }),
        ),
      if (repair != null)
        if (withdrawnOnUnstarted(repair.round, e) case final gone
            when gone.isNotEmpty)
          _WithdrawnNotice(
            gone: gone,
            onRepair: repairing ? null : () => openRepair(repair.round),
          ),
    ];
    if (allEntered && !visible.every((r) => r.game.outcome.resolved)) {
      allEntered = false;
    }
    // No boards drawn unless the table below is: a jump must not use
    // positions from the last sheet drawn.
    _sheet = SheetLayout.empty;
    final Widget boardTable;
    if (e.players.isEmpty || sections.isEmpty) {
      final noPlayers = e.players.isEmpty;
      boardTable = _NothingToPair(
        noPlayers: noPlayers,
        noSections: sections.isEmpty,
        action: noPlayers ? widget.onAddPlayers : widget.onNewSection,
      );
    } else if (roundNumbers.isEmpty) {
      boardTable = _BlankSheet(
        event: e,
        sections: sections.toList(),
        everySection: everySection,
        scroll: scroll,
      );
    } else if (visible.isEmpty && !shown.any((x) => x.$2.byes.isNotEmpty)) {
      boardTable = _NoBoards(
        searched: jump.text.trim().isNotEmpty,
        missingOnly: missingOnly,
        allEntered: allEntered,
        doneNode: doneNode,
        onFocusChange: () => setState(() {}),
      );
    } else {
      boardTable = _table(e, shown, visible);
    }
    return PlayerDetailsLayout(
      expandContent: true,
      panel:
          Dock.maybeOf(context) != null &&
              Dock.maybeOf(context)!.id != panelOwner
          ? null
          : assumeFor != null
          ? _AssumePanel(
              controller: c,
              gameId: assumeFor!,
              onClose: closeAssume,
            )
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
      child: _PairingsLayout(
        sectionId: widget.sectionId,
        controller: c,
        roundAction: widget.roundAction,
        onPlayer: showPlayer,
        crosstableHeading: crosstableHeading,
        stackedScroll: stackedScroll,
        boardHeading: boardHeading,
        boardToolbar: boardToolbar,
        notices: notices,
        boardTable: boardTable,
      ),
    );
  }

  /// The boards on their sheet, with one column header that stays put while
  /// they scroll under it, and the status line and keys below.
  Widget _table(Event e, List<(Section, Round)> shown, List<BoardRow> visible) {
    final layout = layoutSheet(
      event: e,
      shown: shown,
      visible: visible,
      selection: selection,
      everySection: widget.sectionId == null,
      missingOnly: missingOnly,
      query: jump.text,
    );
    // Builders, not rows: the list makes only the rows on screen.
    final items = <WidgetBuilder>[
      for (final item in layout.items)
        switch (item) {
          SheetHeading(:final section, :final round) => (_) => _SectionHeading(
            section: section,
            round: round,
            allRounds: selection.allRoundsOf(section),
          ),
          SheetScoreGroup(:final points) => (_) => _ScoreGroup(points: points),
          SheetBoard(:final row, :final before) => (_) => _GameRow(
            controller: c,
            row: row,
            before: before,
            locked: selection.locked(row),
            past: isEarlierRound(row.section, row.round),
            swapping: swapping,
            swapPick: swapPick,
            entryBox: entryBox,
            whiteBox: _scoreBox(row, white: true),
            blackBox: _scoreBox(row, white: false),
            onTap: () => focusBox(row.game.id, true),
            onShowPlayer: showPlayer,
            onPickSwap: pickSwap,
            onWithdraw: withdraw,
          ),
          SheetBye(:final bye, :final round, :final every) => (_) => _ByeRow(
            bye: bye,
            player: e.player(bye.player),
            round: round,
            every: every,
            onShowPlayer: showPlayer,
          ),
        },
    ];
    _sheet = layout;
    return _BoardFrame(scroll: scroll, items: items, footer: _legend(visible));
  }

  /// One player's score box on [row]. Its focus node is made as the row is
  /// built, and only the box Tab enters at is in the traversal order.
  Widget _scoreBox(BoardRow row, {required bool white}) {
    final g = row.game;
    return _ScoreBox(
      controller: c,
      row: row,
      white: white,
      node: box(g.id, white),
      locked: selection.locked(row),
      entry: boxKey(g.id, white) == entryBox,
      onKey: (event) => onKey(row, white, event),
      onFocusChange: () => setState(() {}),
      onTap: () => focusBox(g.id, white),
      onShowPlayer: showPlayer,
    );
  }

  /// Under the boards: whose result the focused box enters, and the keys.
  /// A key that is not a result makes the legend say so.
  Widget _legend(List<BoardRow> visible) {
    final focused = boxes[activeBox]?.hasFocus == true;
    final row = !focused
        ? null
        : visible
              .where(
                (r) =>
                    activeBox == boxKey(r.game.id, true) ||
                    activeBox == boxKey(r.game.id, false),
              )
              .firstOrNull;
    final white = activeBox?.endsWith('-w') ?? true;
    final locked = row != null && selection.locked(row);
    return _Legend(
      line: row == null
          ? null
          : entryContext(
              row,
              c.event!,
              everySection: widget.sectionId == null,
              locked: locked,
              white: white,
            ),
      entered: allEntered
          ? _AllEntered(
              doneNode: doneNode,
              every: rows().every((r) => r.game.outcome.resolved),
              onFocusChange: () => setState(() {}),
            )
          : null,
      invalidKey: invalidKey,
      forfeitRefused: forfeitRefused,
      drawHint: drawHint,
      forfeitHint: row != null && !locked && isForfeit(row.game.outcome)
          ? forfeitKeyHint(row.game.outcome, white: white)
          : null,
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
