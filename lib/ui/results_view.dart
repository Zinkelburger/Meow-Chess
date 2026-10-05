import 'result_format.dart';
import 'result_keys.dart';
import 'player_actions.dart';
import 'quad_pairings_panel.dart';
import '../infrastructure/reports.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/pairing.dart';
import 'dialogs.dart';
import 'result_correction_panel.dart';
import 'player_panel.dart';
import 'player_format.dart';
import 'side_panel.dart';
import 'players_view.dart';
import 'pane_controls.dart';
import 'panels.dart';
import 'theme.dart';

class BoardRow {
  const BoardRow(this.section, this.round, this.game);
  final Section section;
  final Round round;
  final Game game;
}

/// Pairings and results, laid out like the wall sheet: round and result count,
/// then one row per board with a score box either side. Typing 1/W, 0/L or D in
/// one player's box fills in the other. Earlier rounds open read-only.
class ResultsView extends StatefulWidget {
  const ResultsView({
    required this.controller,
    this.sectionId,
    this.roundAction,
    super.key,
  });
  final TournamentController controller;
  final String? sectionId;
  final Widget? roundAction;
  @override
  State<ResultsView> createState() => ResultsViewState();
}

class ResultsViewState extends State<ResultsView> {
  final panel = GlobalKey<PlayerPanelState>();
  String? openPlayerId;

  /// Where the open player panel should start, such as `byes`.
  String? openFocus;
  TournamentController get c => widget.controller;

  void showPlayer(String? id, {String? focus}) {
    if (id != null) {
      Dock.maybeOf(context)?.claim(panelOwner);
    } else if (Dock.maybeOf(context)?.id == panelOwner) {
      Dock.maybeOf(context)?.close();
    }
    setState(() {
      openPlayerId = id;
      openFocus = focus;
      assumeFor = null;
    });
    // Result shortcuts should not fire while inspecting a player.
    FocusManager.instance.primaryFocus?.unfocus();
  }

  final scroll = ScrollController();
  final jump = TextEditingController();

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
  String roundSignature = '';

  String get preference => 'results-${widget.sectionId ?? 'all'}';
  String get panelOwner => 'results-panel-${widget.sectionId ?? 'all'}';
  String? activeBox;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    showAllRounds = sections.any(hasFixedQuadSchedule);
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
      jump.text = saved['search'] as String? ?? '';
      activeBox = saved['box'] as String?;
    }
    ready = true;
    jump.addListener(remember);
    scroll.addListener(remember);
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

  String signature() =>
      sections.map((s) => '${s.id}:${s.rounds.length}').join('|');

  @override
  void didUpdateWidget(covariant ResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = signature();
    // A round was posted or undone: go back to the current round.
    if (roundSignature.isNotEmpty && next != roundSignature) {
      selectedRound = null;
      showAllRounds = sections.any(hasFixedQuadSchedule);
      correcting = nudged = false;
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
    ready = false;
    for (final n in boxes.values) {
      n.dispose();
    }
    scroll.dispose();
    stackedScroll.dispose();
    jump.dispose();
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
            remember();
          }
        });
        return node;
      });

  /// The round of [s] on screen.
  Round? shownRound(Section s) => selectedRound == null
      ? s.rounds.lastOrNull
      : s.rounds.where((r) => r.number == selectedRound).firstOrNull;

  Iterable<Round> shownRounds(Section s) =>
      showAllRounds ? s.rounds : [?shownRound(s)];

  /// An earlier round, whose results change only while correcting.
  bool past(BoardRow row) =>
      row.section.format == Format.swiss &&
      row.round.number < row.section.rounds.length;
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

  void remember() {
    if (!ready) return;
    c.workspaceState.writeMap(preference, {
      'signature': roundSignature,
      'round': selectedRound,
      'allRounds': showAllRounds,
      'search': jump.text,
      'box': activeBox,
      'scroll': scroll.hasClients ? scroll.offset : 0,
    });
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

  /// Later rounds require a review before anything is committed.
  Future<void> enter(
    BoardRow row,
    Outcome outcome, {
    required bool white,
  }) async {
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
      // Later rounds depend on this result, so it opens beside the table.
      openResultCorrection(
        context,
        c,
        row.game.id,
        outcome: outcome,
        onDone: () {
          if (mounted) focusBox(row.game.id, white);
        },
      );
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
      setState(() {});
      advance(row.game.id, white);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      busy = false;
    }
  }

  /// Shows round [n], or the current round when [n] is the latest.
  void pickRound(int? n, int latest) {
    setState(() {
      selectedRound = n == latest ? null : n;
      showAllRounds = false;
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
      case LogicalKeyboardKey.keyA:
        if (!locked(row) && !g.outcome.resolved) assume(g.id);
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
    if (outcome == null) return KeyEventResult.ignored;
    enter(row, outcome, white: white);
    return KeyEventResult.handled;
  }

  void assume(String gameId) {
    setState(() {
      Dock.maybeOf(context)?.claim(panelOwner);
      assumeFor = gameId;
      openPlayerId = null;
    });
  }

  Widget assumePanel(String gameId) => FieldsPanel(
    key: ValueKey('assume-$gameId'),
    controller: c,
    draftKey: 'draft-assume-$gameId',
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
        for (final r in shownRounds(s)) (s, r),
    ];
    final all = rows(), visible = visibleRows();
    final viewingPast = shown.any(
      (x) => x.$1.format == Format.swiss && x.$2.number < x.$1.rounds.length,
    );
    final latest = roundNumbers.lastOrNull;
    final player = e.players.where((p) => p.id == openPlayerId).firstOrNull;
    if (assumeFor != null && !all.any((r) => r.game.id == assumeFor)) {
      assumeFor = null;
    }
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
    final boardToolbar = _strip(context, shown, viewingPast);
    // Notices belong to the boards, so they sit in the boards pane and never
    // push the crosstable beside it down.
    final notices = [
      for (final s in sections)
        if (c.quadScheduleIssues[s.id] case final issue?)
          _scheduleIssue(context, s, issue),
      if (swapping) _swapBanner(context, shown.single.$2),
    ];
    final boardTable = roundNumbers.isEmpty
        ? _blankTable(context)
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
                : 'Try another name or board number.',
          )
        : _table(context, shown, visible, latest);
    return PlayerDetailsLayout(
      expandContent: true,
      panel:
          Dock.maybeOf(context) != null &&
              Dock.maybeOf(context)!.id != panelOwner
          ? null
          : assumeFor != null
          ? assumePanel(assumeFor!)
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
          final paneWidth = math.min(
            (layout.maxWidth - gutter) / 2,
            560 * scale,
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
                      width: math.min(layout.maxWidth, 560 * scale),
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
          if (viewingPast) line(_pastStatus(context)),
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
          if (viewingPast && correcting)
            FilledButton(
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
            tooltip: 'Print packet',
            onPressed: shown.isEmpty ? null : printRound,
            icon: const Icon(Icons.print_outlined, size: 18),
          ),
        ],
      ),
    );
  }

  /// Shown while an earlier round is on screen, so nobody enters this
  /// round's results there by mistake. Typing into a locked box says how.
  Widget _pastStatus(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = correcting ? colors.error : colors.onSurfaceVariant;
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
                ? 'Read-only · choose Correct a result to change it'
                : 'Read-only',
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
    final items = <Widget>[];
    for (final (s, r) in ordered) {
      final boards = bySection[(s.id, r.number)] ?? const <BoardRow>[];
      final byes = missingOnly
          ? const <ByeAward>[]
          : r.byes.where((b) => named(e.player(b.player))).toList();
      if (boards.isEmpty && byes.isEmpty) continue;
      if (widget.sectionId == null || showAllRounds) {
        items.add(_sectionRow(context, s, r));
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
      for (final b in byes) {
        items.add(_bye(context, b, r.number));
      }
    }
    return _frame(context, items);
  }

  /// The ruled sheet the boards sit on, with a column header that stays put
  /// while the boards scroll under it.
  Widget _frame(BuildContext context, List<Widget> items) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep player names and inline actions readable at enlarged text sizes.
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final width = constraints.maxWidth.clamp(520 * scale, 560 * scale);
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
                        children: [_columns(context), ...items],
                      )
                    : constraints.maxHeight <
                          MediaQuery.textScalerOf(context).scale(150)
                    ? SingleChildScrollView(
                        controller: scroll,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [_columns(context), ...items],
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _columns(context),
                          Flexible(
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

  static const _board = 40.0, _row = 32.0;
  double scoreWidth(BuildContext context) =>
      math.max(36, MediaQuery.textScalerOf(context).scale(32));

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
            width: _board,
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
    return KeyedSubtree(
      key: const ValueKey('blank-board-sheet'),
      child: Semantics(
        label: 'Boards appear here when pairings are created.',
        child: _frame(context, items),
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
            const SizedBox(width: _board, child: Text('Board')),
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
        showAllRounds ? '${s.name} · Round ${r.number}' : s.name,
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
  Widget _bye(BuildContext context, ByeAward b, int round) {
    final colors = Theme.of(context).colorScheme;
    final p = c.event!.player(b.player);
    return Container(
      key: ValueKey(showAllRounds ? 'bye-${p.id}-$round' : 'bye-${p.id}'),
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
            width: _board,
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
                    child: InkWell(
                      key: ValueKey(
                        showAllRounds
                            ? 'bye-player-${p.id}-$round'
                            : 'bye-player-${p.id}',
                      ),
                      onTap: () => showPlayer(p.id),
                      child: Text(p.name, style: const TextStyle(fontSize: 14)),
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
      final playerLink = Tooltip(
        message: '${p.name} · Double-click or press Enter for player details',
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
            TextButton(
              key: ValueKey('withdraw-${g.id}-${p.id}'),
              onPressed: () {
                try {
                  c.savePlayer(c.event!.player(p.id).copy(withdrawn: true));
                } catch (error) {
                  if (mounted) showFailure(context, error);
                }
              },
              child: const Text('Withdraw from future rounds'),
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
                width: _board,
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
    );
  }
}
