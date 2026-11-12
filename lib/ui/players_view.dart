import 'result_keys.dart';
import 'player_actions.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/tournament_controller.dart';
import 'rating_refresh.dart';
import 'rating_review_panel.dart';
import '../domain/eligibility.dart';
import '../domain/fide.dart';
import '../domain/model.dart';
import 'membership_style.dart';
import '../domain/pairing.dart';
import '../domain/standings.dart';
import '../domain/team_standings.dart' show TeamAwards;
import '../domain/scheveningen.dart';
import '../domain/rating_preview.dart';
import 'dialogs.dart';
import 'result_correction_panel.dart';
import 'roster_import_panel.dart';
import '../infrastructure/roster_import.dart' show decodeRosterText;
import 'panels.dart' show FieldsPanel, Dock, showPrint;
import '../infrastructure/reports.dart' show ReportKind;
import 'players_view_model.dart';
import 'theme.dart';
import 'result_format.dart';

import 'fide_list_panel.dart';
import 'side_panel.dart';
import 'player_format.dart';
import 'player_panel.dart';
import 'paste_roster_panel.dart';
import 'pane_controls.dart';
import 'new_section_panel.dart';
import 'formats/knockout_view.dart';
import 'team_standings_view.dart';
import 'workspace_status.dart' show showUndoNotice;

export 'players_view_model.dart' show pairingNumbers;

part 'players_view_widgets.dart';

class PlayersView extends StatefulWidget {
  const PlayersView({
    required this.controller,
    this.sectionId,
    this.onRefreshRoster,
    this.onRefreshRatings,
    this.newSectionRequested = false,
    this.onNewSectionShown,
    this.onSectionsCreated,
    this.ratingRefresh,
    this.roundAction,
    this.standingsOnly = false,
    this.onPlayer,
    this.standingsLayout,
    super.key,
  });
  final TournamentController controller;
  final String? sectionId;
  final VoidCallback? onRefreshRoster, onRefreshRatings;

  /// The workspace's New section button was pressed: open (or close) the
  /// New section panel, then report it with [onNewSectionShown].
  final bool newSectionRequested;
  final VoidCallback? onNewSectionShown;
  final ValueChanged<List<String>>? onSectionsCreated;
  final RatingRefresh? ratingRefresh;
  final Widget? roundAction;
  final bool standingsOnly;

  /// Embedded crosstables open details in their parent workspace, optionally
  /// at one part of the player panel (for example `byes`).
  final void Function(String id, {String? focus})? onPlayer;

  /// Allows Pairings to align headings, toolbars, and tables in shared rows.
  final Widget Function(Widget heading, Widget toolbar, Widget table)?
  standingsLayout;
  @override
  State<PlayersView> createState() => _PlayersViewState();
}

class _PlayersViewState extends State<PlayersView> {
  final search = TextEditingController();

  /// The ticked players, and a move or swap reviewed for them.
  final picks = PlayerSelection();

  /// The ticked players, read-only: change them through [picks], so a
  /// pending move or swap goes with them.
  Set<String> get selected => picks.ticked;
  final panel = GlobalKey<PlayerPanelState>();

  /// What the right-hand column shows. New things appear there, never
  /// above the table, so rows stay where the TD left them.
  PlayersSide? side;

  /// A finished action, confirmed at the right with Undo and Done.
  String? doneTitle, doneMessage;
  int? doneHead;

  void showDone(String title, String message) {
    doneTitle = title;
    doneMessage = message;
    doneHead = c.graph.head;
    // A card kept open by an edit it cannot save keeps the column; the
    // change is confirmed in the window's notice instead.
    if (!showSide(PlayersSide.done)) showUndoNotice(context, c, message);
  }

  void imported(String summary) => showDone('Import saved', summary);

  /// Where the column returns when a panel closes: the ticked players'
  /// actions, then an open rating review, then nothing.
  PlayersSide? get restingSide => restingSideFor(
    ticked: selected.isNotEmpty,
    reviewing: refreshDraft != null && !widget.standingsOnly,
  );

  void closeSide() => showSide(restingSide);

  /// Ticking players shows what can be done with them, unless a form is open.
  void selectionChanged() {
    final next = sideAfterTicking(
      side,
      ticked: selected.isNotEmpty,
      resting: restingSide,
    );
    if (next.change) showSide(next.side);
  }

  void tick(Iterable<String> ids, bool value) {
    setState(() => picks.tick(ids, value));
    selectionChanged();
  }

  void clearSelection() => tick(selected.toList(), false);

  /// Shift-click ticks or unticks every visible row from the last one.
  void tickRow(String id, bool value) {
    tick(
      picks.clickRange(
        [for (final p in order) p.id],
        id,
        shift: HardwareKeyboard.instance.isShiftPressed,
      ),
      value,
    );
    picks.anchor = id;
  }

  /// Whether a rating review was open when last seen.
  bool reviewing = false;

  /// The player shown when [side] is [PlayersSide.player].
  String? open;
  final moveReason = TextEditingController();

  /// Players in on-screen order, for arrow-key movement.
  List<Player> order = const [];
  final resultFocus = <String, FocusNode>{};
  List<String>? entryOrder;
  String? activeResult;
  bool enteringResult = false;

  /// A score cell's focus. Each cell keeps itself out of the Tab order
  /// unless it is the [entryCell].
  FocusNode standingFocus(Game g, String player) => resultFocus.putIfAbsent(
    cellKey(g.id, player),
    () =>
        FocusNode(debugLabel: 'standing-${g.id}-$player', skipTraversal: true),
  );

  /// The crosstable is one Tab stop: Tab enters at this cell (the active
  /// one, or the first missing a result), and every other cell is reached
  /// with the arrows. Chosen from the rows each build.
  String? entryCell;

  void focusStanding(Game game, String player) {
    entryOrder ??= order.map((p) => p.id).toList();
    activeResult = cellKey(game.id, player);
    remember();
    final node = standingFocus(game, player)..requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (node.context case final context? when context.mounted) {
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  /// The games each listed player has a score cell for, rounds left to
  /// right: where Left and Right move.
  Map<String, List<Game>> cellGames = const {};

  /// A printable key that is not a result was typed in a cell.
  bool invalidKey = false;

  KeyEventResult standingKey(
    Player p,
    Section section,
    int round,
    Game game,
    KeyEvent event,
  ) {
    final keyboard = HardwareKeyboard.instance;
    CellKeyPress press([Outcome? outcome]) => CellKeyPress(
      switch (event.logicalKey) {
        LogicalKeyboardKey.arrowUp => CellKey.up,
        LogicalKeyboardKey.arrowDown => CellKey.down,
        LogicalKeyboardKey.arrowLeft => CellKey.left,
        LogicalKeyboardKey.arrowRight => CellKey.right,
        LogicalKeyboardKey.enter ||
        LogicalKeyboardKey.numpadEnter => CellKey.enter,
        LogicalKeyboardKey.space => CellKey.details,
        _ => CellKey.other,
      },
      release: event is KeyUpEvent,
      repeat: event is KeyRepeatEvent,
      modified:
          keyboard.isControlPressed ||
          keyboard.isMetaPressed ||
          keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
      outcome: outcome,
      printable: (event.character ?? '').trim().isNotEmpty,
    );
    // Key-ups and shortcuts are most of what arrives: let them go before
    // walking the rows.
    if (press().passesOn) return KeyEventResult.ignored;
    final cells = roundCells(order, c.pairingEvent, round);
    final action = cellKeyAction(
      press(
        resultFromKey(event, white: game.white == p.id, current: game.outcome),
      ),
      player: p.id,
      game: game,
      cells: cells,
      games: cellGames[p.id] ?? const <Game>[],
      entering: enteringResult,
    );
    switch (action) {
      case CellKeyIgnored():
        return KeyEventResult.ignored;
      case CellKeySwallowed():
        break;
      case CellMove(:final player, :final game):
        focusStanding(game, player);
      case CellShowPlayer():
        openPlayer(p.id);
      case CellRefuse():
        setState(() => invalidKey = true);
      case CellEnter(:final outcome, :final save):
        if (invalidKey) setState(() => invalidKey = false);
        if (save) {
          saveStandingResult(
            p,
            section,
            round,
            game,
            outcome,
            cells,
            cellIndex(cells, p.id, game.id),
          );
        }
    }
    return KeyEventResult.handled;
  }

  Future<void> saveStandingResult(
    Player p,
    Section section,
    int round,
    Game game,
    Outcome outcome,
    List<(Player, Game)> cells,
    int index,
  ) async {
    enteringResult = true;
    try {
      if (c.correctionHasDependencies(game.id)) {
        openResultCorrection(
          context,
          c,
          game.id,
          outcome: outcome,
          white: game.white == p.id,
        );
        return;
      }
      final before = game.outcome;
      c.recordResult(game.id, outcome);
      // A recorded result was replaced or cleared by one key: never silently.
      if (mounted && before != Outcome.unreported && before != outcome) {
        showUndoNotice(
          context,
          c,
          [
            if (widget.sectionId == null) section.name,
            if (round != section.rounds.length) 'Round $round',
            resultChangeText(game.board, before, outcome),
          ].join(' · '),
        );
      }
      if (outcome.resolved) {
        final next = nextMissingCell(
          cells,
          index,
          game.id,
          (id) => c.pairingEvent.games.firstWhere((g) => g.id == id).outcome,
        );
        if (next != null && mounted) focusStanding(next.$2, next.$1.id);
      }
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      enteringResult = false;
    }
  }

  /// A score cell gained or lost focus. Leaving the crosstable lets the
  /// rows take their standings order again.
  void cellFocusChanged(Game g, String player, bool hasFocus) {
    if (!mounted) return;
    if (!hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !enteringResult &&
            !resultFocus.values.any((node) => node.hasFocus)) {
          setState(() {
            entryOrder = null;
            invalidKey = false;
          });
        }
      });
    }
    if (hasFocus) {
      entryOrder ??= order.map((p) => p.id).toList();
      activeResult = cellKey(g.id, player);
    }
    setState(() {});
  }

  /// The columns the table shows, worked out each build. Rule 34B: the
  /// posted tie-break methods are shown beside the points, in order, once
  /// the event ranks by them.
  late ShownColumns columns;

  /// Rule 30B on screen: standings without early round-robin withdrawals.
  bool prizeStandings = false;

  bool showIds = true;

  /// The sections this view lists: one, or all of them.
  Iterable<Section> get viewedSections => c.event!.sections.where(
    (s) => widget.sectionId == null || s.id == widget.sectionId,
  );

  /// US Chess columns are left out where nothing listed is US Chess rated
  /// (a FIDE-only section or event).
  bool get usChessView =>
      viewedSections.isEmpty || viewedSections.any((s) => !s.unrated);

  bool showRatingPreview = false;
  TournamentController get c => widget.controller;
  RatingRefresh? get refreshDraft =>
      widget.ratingRefresh?.active == true ? widget.ratingRefresh : null;

  String get preference =>
      '${widget.standingsOnly ? 'standings' : 'players'}-view-${widget.sectionId ?? 'all'}';
  final scroll = ScrollController();
  String get panelOwner => 'players-panel-${widget.sectionId ?? 'all'}';
  bool ready = false;

  @override
  void initState() {
    super.initState();
    widget.ratingRefresh?.addListener(refreshRatingsView);
    final saved = c.workspaceState.readMap(preference);
    final restored = SavedPlayersView.fromMap(saved);
    search.text = restored.search;
    open = restored.open;
    picks.tick(restored.selected, true);
    reviewing = refreshDraft != null;
    side = restoredSide(
      restored.side,
      reviewing: reviewing,
      ticked: selected.isNotEmpty,
    );
    activeResult = restored.activeResult;
    showRatingPreview = !widget.standingsOnly && restored.showRatingPreview;
    prizeStandings = widget.standingsOnly && restored.prizeStandings;
    picks.moveTo = restored.moveTo;
    moveReason.text = restored.moveReason;
    // The revision the move or swap was reviewed at comes back with it, so
    // it still applies after a visit to another page, and is still refused
    // when the event changed meanwhile.
    picks.moveRevision = restored.moveRevision;
    picks.swapping =
        restored.swapping && picks.moveRevision != null && selected.length == 2;
    if (picks.moveTo != null &&
        (picks.moveRevision == null ||
            !c.event!.sections.any((s) => s.id == picks.moveTo))) {
      picks.moveTo = null;
    }
    ready = true;
    search.addListener(remember);
    moveReason.addListener(remember);
    scroll.addListener(scrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scrollOffset = SavedPlayersView.scrollOf(saved);
      if (scroll.hasClients) {
        scroll.jumpTo(scrollOffset.clamp(0, scroll.position.maxScrollExtent));
      }
      if (side != null) {
        Dock.maybeOf(context)?.claim(panelOwner);
      } else {
        resultFocus[activeResult]?.requestFocus();
      }
      answerNewSection();
    });
  }

  void answerNewSection() {
    if (!widget.newSectionRequested || !mounted) return;
    widget.onNewSectionShown?.call();
    // A form hidden behind History or another tool is shown, not closed.
    final dock = Dock.maybeOf(context);
    final shown =
        side == PlayersSide.newSection &&
        (dock == null || dock.id == panelOwner);
    showSide(shown ? restingSide : PlayersSide.newSection);
  }

  void sectionsCreated(List<String> ids) {
    setState(() {
      picks.clear();
      side = null;
    });
    if (Dock.maybeOf(context)?.id == panelOwner) Dock.maybeOf(context)?.close();
    widget.onSectionsCreated?.call(ids);
  }

  /// Starting a review opens it at the right; finishing it closes it.
  void refreshRatingsView() {
    if (!mounted) return;
    final now = refreshDraft != null;
    if (!widget.standingsOnly && now != reviewing) {
      reviewing = now;
      if (now) {
        showSide(PlayersSide.ratingReview);
        return;
      }
      if (side == PlayersSide.ratingReview) return closeSide();
    }
    setState(() {});
  }

  void confirmRatings(RatingRefresh draft) {
    try {
      final count = draft.apply();
      showDone(
        'US Chess ratings updated',
        'Updated $count US Chess ${count == 1 ? 'rating' : 'ratings'}.',
      );
    } catch (e) {
      showFailure(context, e);
    }
  }

  @override
  void didUpdateWidget(covariant PlayersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.newSectionRequested && !oldWidget.newSectionRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) => answerNewSection());
    }
    if (oldWidget.ratingRefresh != widget.ratingRefresh) {
      oldWidget.ratingRefresh?.removeListener(refreshRatingsView);
      widget.ratingRefresh?.addListener(refreshRatingsView);
    }
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

  void remember() {
    if (!ready) return;
    scrollSave?.cancel();
    scrollSave = null;
    c.workspaceState.writeMap(
      preference,
      SavedPlayersView(
        search: search.text,
        open: open,
        side: side,
        selected: selected.toList(),
        activeResult: activeResult,
        showRatingPreview: showRatingPreview,
        prizeStandings: prizeStandings,
        moveTo: picks.moveTo,
        moveRevision: picks.moveRevision,
        swapping: picks.swapping,
        moveReason: moveReason.text,
        scroll: scroll.hasClients ? scroll.offset : scrollOffset,
      ).toMap(),
    );
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    remember();
  }

  @override
  void dispose() {
    remember();
    scrollSave?.cancel();
    widget.ratingRefresh?.removeListener(refreshRatingsView);
    scroll.dispose();
    search.dispose();
    moveReason.dispose();
    for (final node in resultFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Changes the panel. A player's card saves its pending edit first; when
  /// that edit cannot be saved the card stays open on the problem and this
  /// returns false. The Add form keeps what was typed as a draft.
  bool showSide(PlayersSide? next, [String? id]) {
    if (side == PlayersSide.player &&
        (next != PlayersSide.player || id != open) &&
        !(panel.currentState?.applyEdits() ?? true)) {
      return false;
    }
    if (next != null) {
      Dock.maybeOf(context)?.claim(panelOwner);
    } else if (Dock.maybeOf(context)?.id == panelOwner) {
      Dock.maybeOf(context)?.close();
    }
    if (next == side && id == open) return true;
    setState(() {
      side = next;
      open = id;
    });
    return true;
  }

  Future<void> importFile() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Player list',
            extensions: ['csv', 'tsv', 'txt'],
            mimeTypes: ['text/csv', 'text/tab-separated-values', 'text/plain'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final source = decodeRosterText(await file.readAsBytes());
      if (!mounted) return;
      final summary = await showRosterImport(
        context,
        controller: c,
        source: source,
        filename: file.name,
      );
      if (summary != null && mounted) imported(summary);
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  /// Where the open player panel should start, such as `byes`.
  String? openFocus;

  void openPlayer(String id, {String? focus}) {
    if (widget.onPlayer case final onPlayer?) {
      onPlayer(id, focus: focus);
    } else if (side == PlayersSide.player && open == id) {
      // The card may be hidden behind History or another tool.
      Dock.maybeOf(context)?.claim(panelOwner);
      setState(() => openFocus = focus);
    } else {
      openFocus = focus;
      showSide(PlayersSide.player, id);
    }
  }

  Widget _detailsLayout({required Widget child, Widget? panel}) =>
      widget.onPlayer != null
      ? child
      : PlayerDetailsLayout(expandContent: true, panel: panel, child: child);

  /// Moves the ticked players. Before play that is a roster edit and
  /// happens at once, with Undo; once a section involved has been paired the
  /// move is a transfer, reviewed with a reason in the selection panel first.
  void moveSelected(String targetId, {String reason = ''}) {
    final e = c.event!;
    final played = e.sections
        .where((s) => s.id == targetId || s.players.any(selected.contains))
        .any((s) => s.rounds.isNotEmpty);
    final staged = picks.moveTo == targetId;
    if (played && !staged) {
      setState(() {
        picks.moveTo = targetId;
        picks.moveRevision = e.revision;
      });
      return;
    }
    try {
      if (staged && picks.moveRevision != e.revision) {
        setState(() => picks.moveTo = null);
        throw const TournamentException(
          'The event changed. Choose the destination and review again.',
        );
      }
      final count = selected.length;
      final sources = {for (final id in selected) ?e.sectionOf(id)?.id};
      c.movePlayers(selected.toList(), targetId, reason: reason);
      setState(picks.clear);
      moveReason.clear();
      showDone(
        'Players moved',
        [
          'Moved $count ${count == 1 ? 'player' : 'players'} to '
              '${c.event!.sections.firstWhere((s) => s.id == targetId).name}.',
          ?rosterNote(c.event!, {...sources, targetId}, before: e),
        ].join(' '),
      );
    } catch (e) {
      showFailure(context, e);
    }
  }

  void confirmMove() {
    final reason = moveReason.text.trim();
    moveSelected(picks.moveTo!, reason: reason);
  }

  /// Removes, withdraws or reinstates players, then confirms it with Undo.
  /// Acting on the ticked players clears the ticks.
  void applyStatusTo(StatusAction action, List<String> ids) {
    try {
      final done = applyStatus(c, action, ids);
      if (ids.toSet().containsAll(selected)) {
        setState(picks.clear);
      }
      showDone(done.title, done.message);
    } catch (e) {
      showFailure(context, e);
    }
  }

  /// Delete on a focused row removes it, or every ticked player when it is
  /// one of them. Played players are withdrawn instead, never by a key.
  void removeFromKey(String id) {
    final e = c.event!;
    final ids = selected.contains(id) ? selected.toList() : [id];
    final blocked = ids.map((id) => removeBlocker(e, id)).nonNulls.firstOrNull;
    if (blocked != null) {
      return showFailure(context, TournamentException(blocked));
    }
    applyStatusTo(StatusAction.remove, ids);
  }

  /// Two ticked players can exchange sections only when a quad or round
  /// robin is involved and neither section is paired; a Swiss uses Move.
  bool canSwapPair(Event e) {
    final a = e.sectionOf(selected.first), b = e.sectionOf(selected.last);
    return a != null && b != null && swapAllowed(a, b);
  }

  /// The first press asks to confirm the swap of the two ticked players,
  /// reviewed at the revision of [e]; the second makes it.
  void swapSelected(Event e) {
    if (!picks.swapping) {
      setState(() {
        picks.swapping = true;
        picks.moveRevision = e.revision;
      });
      return;
    }
    try {
      final a = e.player(selected.first).name;
      final b = e.player(selected.last).name;
      c.swapPlayers(selected.first, selected.last, picks.moveRevision!);
      setState(picks.clear);
      showDone(
        'Players swapped',
        [
          '$a and $b changed places.',
          ?pairingsResetNote(e, c.event!),
        ].join(' '),
      );
    } catch (error) {
      showFailure(context, error);
      setState(() => picks.swapping = false);
    }
  }

  /// Keeps the two ticked players apart in pairings where another pairing
  /// exists.
  void avoidSelected(Event e) {
    try {
      final a = e.player(selected.first).name;
      final b = e.player(selected.last).name;
      final head = c.graph.head;
      c.avoidPair(selected.first, selected.last, true);
      // Nothing to confirm or undo when it was already there.
      if (c.graph.head == head) return clearSelection();
      setState(picks.clear);
      showDone(
        'Request saved',
        '$a and $b will not be paired together where another '
            'pairing exists. To allow it again, open either '
            'player’s card and remove it under Pairing requests.',
      );
    } catch (e) {
      showFailure(context, e);
    }
  }

  void undoDone() {
    try {
      c.undo();
      closeSide();
    } catch (error) {
      showFailure(context, error);
    }
  }

  void printList({required Event event, required bool ranked}) => showPrint(
    context,
    event,
    sectionId: widget.sectionId,
    kind: ranked ? ReportKind.standings : ReportKind.sections,
  );

  void searchSubmitted() {
    final first = order.firstOrNull;
    if (first != null) openPlayer(first.id);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.standingsOnly ? c.pairingEvent : c.event!;
    if (side == PlayersSide.player && !e.players.any((p) => p.id == open)) {
      side = open = null;
    }
    picks.keepOnly(e.players);
    // Undo can remove the section a move was waiting for.
    if (picks.moveTo != null &&
        !c.event!.sections.any((s) => s.id == picks.moveTo)) {
      picks.moveTo = null;
    }
    if ((side == PlayersSide.team || side == PlayersSide.selection) &&
        selected.isEmpty) {
      side = restingSide;
    }
    if (side == PlayersSide.ratingReview && refreshDraft == null) side = null;
    final coordinator = Dock.maybeOf(context);
    final visibleSide = coordinator == null || coordinator.id == panelOwner
        ? side
        : null;
    final panelWidget = switch (visibleSide) {
      PlayersSide.player => PlayerPanel(
        key: panel,
        controller: c,
        player: e.player(open!),
        focusField: openFocus,
        ratingReview: widget.standingsOnly ? null : refreshDraft,
        onBackToReview: () => showSide(PlayersSide.ratingReview),
        onRemoved: showDone,
        onClose: closeSide,
      ),
      PlayersSide.add => PlayerPanel(
        key: panel,
        controller: c,
        sectionId: widget.sectionId,
        onClose: closeSide,
      ),
      PlayersSide.paste => PasteRosterPanel(
        controller: c,
        onClose: closeSide,
        onImported: imported,
      ),
      PlayersSide.team => _TeamPanel(
        controller: c,
        ids: selected.toList(),
        onClose: closeSide,
      ),
      PlayersSide.newSection => NewSectionPanel(
        controller: c,
        ticked: {...selected},
        onCreated: sectionsCreated,
        onClose: closeSide,
      ),
      PlayersSide.selection => _selectionPanel(),
      PlayersSide.ratingReview => RatingReviewPanel(
        draft: refreshDraft!,
        onClose: () =>
            showSide(selected.isEmpty ? null : PlayersSide.selection),
        onConfirm: () => confirmRatings(refreshDraft!),
        onOpenPlayer: openPlayer,
        onAddId: (id) => openPlayer(id, focus: 'memberId'),
      ),
      PlayersSide.done => _DonePanel(
        title: doneTitle ?? 'Saved',
        message: doneMessage ?? '',
        canUndo: c.graph.head == doneHead,
        onUndo: undoDone,
        onClose: closeSide,
      ),
      null => null,
    };
    if (e.players.isEmpty && !widget.standingsOnly) {
      return _detailsLayout(
        panel: panelWidget,
        child: _Welcome(
          onRefreshRoster: widget.onRefreshRoster,
          onImport: importFile,
          onPaste: () => showSide(PlayersSide.paste),
          onAdd: () => showSide(PlayersSide.add),
        ),
      );
    }
    final layout = layoutRoster(
      e,
      sectionId: widget.sectionId,
      standingsOnly: widget.standingsOnly,
      query: search.text,
      prizeStandings: prizeStandings,
      entryOrder: entryOrder,
    );
    final started = layout.started, ranked = started;
    order = layout.order;
    cellGames = layout.cellGames;
    entryCell = widget.standingsOnly
        ? entryCellFor(order, cellGames, activeResult)
        : null;
    columns = ShownColumns.of(
      standingsOnly: widget.standingsOnly,
      // Ticks are acted on in the column beside the table, which an
      // embedded crosstable leaves to its parent.
      checkboxes: widget.onPlayer == null,
      started: started,
      reviewing: refreshDraft != null,
      ratingPreview: showRatingPreview,
      showIds: showIds,
      usChessView: usChessView,
      fideListed: viewedSections.any((s) => s.fideRated),
      rounds: layout.rounds,
      tiebreaks: layout.tiebreakColumns,
    );
    final items = <Widget>[
      for (final (s, players) in layout.groups) ...[
        if (!widget.standingsOnly || widget.sectionId == null)
          _GroupHeader(
            section: s,
            players: players,
            picked: players.where((p) => selected.contains(p.id)).length,
            checkbox: columns.checkbox,
            standingsOnly: widget.standingsOnly,
            onTick: tick,
          ),
        if (players.isEmpty) _EmptyGroup(standingsOnly: widget.standingsOnly),
        // A knockout places by its bracket, not by points.
        if (widget.standingsOnly && s != null && s.format == Format.knockout)
          KnockoutBracketView(controller: c, section: s)
        else
          for (final p in players)
            _row(
              s == null ? '' : '${layout.numbers[p.id] ?? ''}',
              p,
              s,
              s == null ? null : layout.tables[s.id]?[p.id],
              rank: '${layout.ranks[p.id] ?? ''}',
            ),
        // Scholastic team awards: the Teams table under the individuals.
        if (widget.standingsOnly &&
            s != null &&
            s.rounds.isNotEmpty &&
            search.text.isEmpty &&
            TeamAwards.tryOf(s) != null)
          TeamStandingsTable(event: e, section: s),
      ],
    ];
    final table = _RosterTable(
      items: items,
      width: columns.width,
      scroll: scroll,
      standingsOnly: widget.standingsOnly,
      searched: search.text.trim().isNotEmpty,
      columns: _ColumnHeader(columns: columns, draft: refreshDraft),
    );
    if (widget.standingsOnly) {
      // A Scheveningen shows its match score beside the title.
      final match = e.sections
          .where(
            (s) =>
                s.id == widget.sectionId &&
                s.format == Format.scheveningen &&
                scheveningenProblem(e, s) == null,
          )
          .firstOrNull;
      final heading = _CrosstableHeading(
        matchScore: match == null ? null : scheveningenScoreLine(e, match),
      );
      final toolbar = _CrosstableToolbar(
        search: search,
        onSearchChanged: () => setState(() {}),
        onSearchSubmitted: searchSubmitted,
        onPrint: e.sections.isNotEmpty
            ? () => printList(event: c.event!, ranked: ranked)
            : null,
        ranked: ranked,
        prizeSection: layout.prizeSection,
        prizeStandings: prizeStandings,
        onPrizeStandings: (v) {
          setState(() => prizeStandings = v);
          remember();
        },
        tiebreakColumns: columns.tiebreaks,
        invalidKey: invalidKey,
      );
      return _detailsLayout(
        panel: panelWidget,
        child:
            widget.standingsLayout?.call(heading, toolbar, table) ??
            Column(
              key: const ValueKey('standings-pane'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                toolbar,
                Expanded(child: table),
              ],
            ),
      );
    }
    return _detailsLayout(
      panel: panelWidget,
      child: _RosterPage(
        controller: c,
        search: search,
        onSearchChanged: () => setState(() {}),
        onSearchSubmitted: searchSubmitted,
        tools: _PlayerTools(
          controller: c,
          onRefreshRoster: widget.onRefreshRoster,
          onImport: importFile,
          onPaste: () => showSide(PlayersSide.paste),
          showRatingPreview: showRatingPreview,
          onShowRatingPreview: (value) =>
              setState(() => showRatingPreview = value ?? false),
          showIds: showIds,
          onShowIds: (v) => setState(() => showIds = v!),
        ),
        onAdd: () => showSide(PlayersSide.add),
        fideOnly: !usChessView && refreshDraft == null,
        onRefreshRatings: refreshDraft == null
            ? widget.onRefreshRatings
            : () => showSide(PlayersSide.ratingReview),
        refreshable: widget.onRefreshRatings != null,
        title: '${layout.shown} ${layout.shown == 1 ? 'player' : 'players'}',
        onPrint: e.sections.isNotEmpty
            ? (context) => showPrint(
                context,
                e,
                sectionId: widget.sectionId,
                kind: ranked ? ReportKind.standings : ReportKind.sections,
              )
            : null,
        ranked: ranked,
        table: table,
      ),
    );
  }

  /// Bulk actions for the ticked players, in the right-hand column so the
  /// table never moves when a box is ticked.
  Widget _selectionPanel() {
    final e = c.event!;
    return _SelectionPanel(
      event: e,
      ids: selected.toList(),
      moveTo: picks.moveTo,
      moveReason: moveReason,
      swapping: picks.swapping,
      canSwap: selected.length == 2 && canSwapPair(e),
      onClear: clearSelection,
      onConfirmMove: confirmMove,
      onCancelMove: () => setState(() => picks.moveTo = null),
      onMoveTo: moveSelected,
      onNewSection: () => showSide(PlayersSide.newSection),
      onSwap: () => swapSelected(e),
      onAvoid: () => avoidSelected(e),
      onTeam: () => showSide(PlayersSide.team),
      onStatus: applyStatusTo,
    );
  }

  /// One player's row, with what it does when clicked, ticked, keyed or
  /// right-clicked.
  Widget _row(
    String number,
    Player p,
    Section? s,
    Standing? standing, {
    String rank = '',
  }) {
    void menu(Offset at) => showPlayerMenu(
      context,
      c,
      p.id,
      at,
      onByes: (id) => openPlayer(id, focus: 'byes'),
      group: selected,
      onMoveGroup: moveSelected,
      onStatus: applyStatusTo,
    );
    return _PlayerRow(
      event: c.event!,
      player: p,
      section: s,
      number: number,
      rank: rank,
      standing: standing,
      ticked: selected.contains(p.id),
      open: open == p.id,
      standingsOnly: widget.standingsOnly,
      columns: columns,
      draft: refreshDraft,
      roundCells: [
        for (var r = 1; r <= columns.rounds; r++) _roundCell(p, s, r),
      ],
      onMenu: menu,
      onRemove: () => removeFromKey(p.id),
      onOpen: () => openPlayer(p.id),
      onTick: (value) => tickRow(p.id, value),
    );
  }

  /// [p]'s cell for round [r]: a score box for each game, focused and keyed
  /// here, or a bye mark.
  Widget _roundCell(Player p, Section? s, int r) {
    if (s != null && r > s.plannedRounds) return const _RoundCell.blank();
    final (mark, tip) = roundCellText(c.event!, p, s, r);
    final games = s == null ? const <Game>[] : gamesOf(s, r, p.id);
    return _RoundCell(
      boxKey: ValueKey('round-${p.id}-$r'),
      mark: mark,
      tip: tip,
      boxes: [
        for (final g in games)
          _CellBox(
            game: g,
            player: p,
            round: r,
            node: standingFocus(g, p.id),
            focused: standingFocus(g, p.id).hasFocus,
            entry: cellKey(g.id, p.id) == entryCell,
            label:
                '${p.name}, round $r, ${games.length > 1 ? 'game ${g.leg}, ' : ''}$tip. $resultKeyHint · Space player details',
            tip: tip,
            onKey: (event) => standingKey(p, s!, r, g, event),
            onFocusChange: (hasFocus) => cellFocusChanged(g, p.id, hasFocus),
            onTap: () => focusStanding(g, p.id),
          ),
      ],
    );
  }
}

String formatName(Format f) => f.label;
