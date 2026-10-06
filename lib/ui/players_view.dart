import 'result_keys.dart';
import 'player_actions.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/tournament_controller.dart';
import 'rating_refresh.dart';
import 'rating_review_panel.dart';
import '../domain/model.dart';
import 'membership_style.dart';
import '../domain/pairing.dart';
import '../domain/standings.dart';
import '../domain/rating_preview.dart';
import 'dialogs.dart';
import 'result_correction_panel.dart';
import 'roster_import_panel.dart';
import 'panels.dart' show FieldsPanel, Dock, showPrint;
import '../infrastructure/reports.dart' show ReportKind;
import 'theme.dart';
import 'result_format.dart';

import 'side_panel.dart';
import 'player_format.dart';
import 'player_panel.dart';
import 'paste_roster_panel.dart';
import 'pane_controls.dart';
import 'new_section_panel.dart';

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
  final selected = <String>{};
  final panel = GlobalKey<PlayerPanelState>();

  /// What the right-hand column shows. New things appear there, never
  /// above the table, so rows stay where the TD left them.
  _Side? side;

  /// A finished action, confirmed at the right with Undo and Done.
  String? doneTitle, doneMessage;
  int? doneHead;

  void showDone(String title, String message) {
    doneTitle = title;
    doneMessage = message;
    doneHead = c.graph.head;
    showSide(_Side.done);
  }

  void imported(String summary) => showDone('Import saved', summary);

  /// Where the column returns when a panel closes: the ticked players'
  /// actions, then an open rating review, then nothing.
  _Side? get restingSide => selected.isNotEmpty
      ? _Side.selection
      : refreshDraft != null && !widget.standingsOnly
      ? _Side.ratingReview
      : null;

  void closeSide() => showSide(restingSide);

  /// Ticking players shows what can be done with them, unless a form is open.
  void selectionChanged() {
    if (selected.isEmpty) {
      if (side == _Side.selection) closeSide();
      return;
    }
    if (side == null ||
        side == _Side.selection ||
        side == _Side.ratingReview ||
        side == _Side.done) {
      showSide(_Side.selection);
    }
  }

  void tick(Iterable<String> ids, bool value) {
    setState(() {
      value ? selected.addAll(ids) : selected.removeAll(ids);
      if (selected.isEmpty) {
        moveTo = null;
        swapping = false;
      }
    });
    selectionChanged();
  }

  void clearSelection() => tick(selected.toList(), false);

  /// The row last ticked or unticked by hand, where a Shift-click range
  /// starts.
  String? anchor;

  /// Shift-click ticks or unticks every visible row from the last one.
  void tickRow(String id, bool value) {
    final ids = [for (final p in order) p.id];
    final from = anchor == null ? -1 : ids.indexOf(anchor!);
    final to = ids.indexOf(id);
    if (HardwareKeyboard.instance.isShiftPressed && from >= 0 && to >= 0) {
      tick(ids.sublist(math.min(from, to), math.max(from, to) + 1), value);
    } else {
      tick([id], value);
    }
    anchor = id;
  }

  /// Whether a rating review was open when last seen.
  bool reviewing = false;

  /// The player shown when [side] is [_Side.player].
  String? open;

  /// A move of the ticked players waiting for a reason.
  String? moveTo;
  int? moveRevision;
  bool swapping = false;
  final moveReason = TextEditingController();

  /// Players in on-screen order, for arrow-key movement.
  List<Player> order = const [];
  final resultFocus = <String, FocusNode>{};
  List<String>? entryOrder;
  String? activeResult;
  bool enteringResult = false;

  FocusNode standingFocus(Game g, String player) => resultFocus.putIfAbsent(
    '${g.id}-$player',
    () => FocusNode(debugLabel: 'standing-${g.id}-$player'),
  );

  void focusStanding(Game game, String player) {
    entryOrder ??= order.map((p) => p.id).toList();
    activeResult = '${game.id}-$player';
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

  List<(Player, Game)> standingCells(int round) => [
    for (final p in order)
      if (c.pairingEvent.sectionOf(p.id) case final section?)
        for (final r in section.rounds.where((r) => r.number == round))
          for (final g in r.games.where(
            (g) => g.white == p.id || g.black == p.id,
          ))
            (p, g),
  ];

  KeyEventResult standingKey(
    Player p,
    Section section,
    int round,
    Game game,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final cells = standingCells(round);
    final index = cells.indexWhere(
      (x) => x.$1.id == p.id && x.$2.id == game.id,
    );
    if ([
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
    ].contains(key)) {
      final direction =
          key == LogicalKeyboardKey.arrowUp ||
              HardwareKeyboard.instance.isShiftPressed
          ? -1
          : 1;
      final next = index + direction;
      if (next >= 0 && next < cells.length) {
        focusStanding(cells[next].$2, cells[next].$1.id);
      }
      return KeyEventResult.handled;
    }
    final outcome = resultFromKey(
      event,
      white: game.white == p.id,
      current: game.outcome,
    );
    if (outcome == null) return KeyEventResult.ignored;
    if (!enteringResult) {
      saveStandingResult(p, section, round, game, outcome, cells, index);
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
        openResultCorrection(context, c, game.id, outcome: outcome);
        return;
      }
      c.recordResult(game.id, outcome);
      if (outcome.resolved) {
        final next = [...cells.skip(index + 1), ...cells.take(index)]
            .where(
              (x) =>
                  x.$2.id != game.id &&
                  !c.pairingEvent.games
                      .firstWhere((g) => g.id == x.$2.id)
                      .outcome
                      .resolved,
            )
            .firstOrNull;
        if (next != null && mounted) focusStanding(next.$2, next.$1.id);
      }
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      enteringResult = false;
    }
  }

  int rounds = 0;

  /// Whether the table shows points and tiebreaks.
  bool scores = false;

  bool showIds = true;

  /// A rating review compares IDs, so it always shows them.
  bool get showsIds =>
      !widget.standingsOnly && (showIds || refreshDraft != null);
  bool showRatingPreview = false;
  TournamentController get c => widget.controller;
  RatingRefresh? get refreshDraft =>
      widget.ratingRefresh?.active == true ? widget.ratingRefresh : null;

  // Fixed column widths keep the table narrow and aligned.
  static const _check = 40.0,
      _number = 28.0,
      _name = 200.0,
      _rating = 64.0,
      _preview = 132.0,
      _proposal = 168.0,
      _uscfName = 200.0,
      _membership = 216.0,
      _note = 240.0,
      _id = 100.0,
      _round = 40.0,
      _points = 40.0;

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
    search.text = saved['search'] as String? ?? '';
    open = saved['open'] as String?;
    side = _Side.values.where((v) => v.name == saved['side']).firstOrNull;
    selected.addAll((saved['selected'] as List? ?? []).whereType<String>());
    reviewing = refreshDraft != null;
    if (side == _Side.done ||
        (side == _Side.ratingReview && !reviewing) ||
        (side == _Side.selection && selected.isEmpty)) {
      side = null;
    }
    activeResult = saved['activeResult'] as String?;
    showRatingPreview =
        !widget.standingsOnly && saved['showRatingPreview'] == true;
    moveTo = saved['moveTo'] as String?;
    moveReason.text = saved['moveReason'] as String? ?? '';
    ready = true;
    search.addListener(remember);
    moveReason.addListener(remember);
    scroll.addListener(remember);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (scroll.hasClients) {
        scroll.jumpTo(
          (saved['scroll'] as num? ?? 0).toDouble().clamp(
            0,
            scroll.position.maxScrollExtent,
          ),
        );
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
    showSide(side == _Side.newSection ? restingSide : _Side.newSection);
  }

  void sectionsCreated(List<String> ids) {
    setState(() {
      selected.clear();
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
      if (now) return showSide(_Side.ratingReview);
      if (side == _Side.ratingReview) return closeSide();
    }
    setState(() {});
  }

  void confirmRatings(RatingRefresh draft) {
    try {
      final count = draft.apply();
      showDone(
        'USCF ratings updated',
        'Updated $count USCF ${count == 1 ? 'rating' : 'ratings'}.',
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

  void remember() {
    if (!ready) return;
    c.workspaceState.writeMap(preference, {
      'search': search.text,
      'open': open,
      'side': side?.name,
      'selected': selected.toList(),
      'activeResult': activeResult,
      'showRatingPreview': showRatingPreview,
      'moveTo': moveTo,
      'moveReason': moveReason.text,
      'scroll': scroll.hasClients ? scroll.offset : 0,
    });
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    remember();
  }

  @override
  void dispose() {
    remember();
    widget.ratingRefresh?.removeListener(refreshRatingsView);
    scroll.dispose();
    search.dispose();
    moveReason.dispose();
    for (final node in resultFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Changes the panel; partial edits remain separate, recoverable drafts.
  void showSide(_Side? next, [String? id]) {
    if (next != null) {
      Dock.maybeOf(context)?.claim(panelOwner);
    } else if (Dock.maybeOf(context)?.id == panelOwner) {
      Dock.maybeOf(context)?.close();
    }
    if (next == side && id == open) return;
    setState(() {
      side = next;
      open = id;
    });
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
      final source = await file.readAsString();
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
    } else if (side == _Side.player && open == id) {
      setState(() => openFocus = focus);
    } else {
      openFocus = focus;
      showSide(_Side.player, id);
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
    final staged = moveTo == targetId;
    if (played && !staged) {
      setState(() {
        moveTo = targetId;
        moveRevision = e.revision;
      });
      return;
    }
    try {
      if (staged && moveRevision != e.revision) {
        moveTo = null;
        throw const TournamentException(
          'The event changed. Choose the destination and review again.',
        );
      }
      final count = selected.length;
      final sources = {for (final id in selected) ?e.sectionOf(id)?.id};
      c.movePlayers(selected.toList(), targetId, reason: reason);
      setState(() {
        selected.clear();
        moveTo = null;
      });
      moveReason.clear();
      showDone(
        'Players moved',
        [
          'Moved $count ${count == 1 ? 'player' : 'players'} to '
              '${c.event!.sections.firstWhere((s) => s.id == targetId).name}.',
          ?rosterNote(c.event!, {...sources, targetId}),
        ].join(' '),
      );
    } catch (e) {
      showFailure(context, e);
    }
  }

  void confirmMove() {
    final reason = moveReason.text.trim();
    moveSelected(moveTo!, reason: reason);
  }

  /// Removes, withdraws or reinstates players, then confirms it with Undo.
  /// Acting on the ticked players clears the ticks.
  void applyStatusTo(StatusAction action, List<String> ids) {
    try {
      final done = applyStatus(c, action, ids);
      if (ids.toSet().containsAll(selected)) {
        setState(() {
          selected.clear();
          moveTo = null;
          swapping = false;
        });
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

  /// Names a team for the ticked players, beside the table.
  Widget teamPanel() {
    final e = c.event!, ids = selected.toList();
    final teams = ids.map((id) => e.player(id).team).toSet();
    return FieldsPanel(
      key: ValueKey('team-${ids.join()}'),
      controller: c,
      draftKey: 'draft-team-${(ids.toList()..sort()).join(',')}',
      title: 'Team for ${ids.length} ${ids.length == 1 ? 'player' : 'players'}',
      description: 'Leave blank to remove the team.',
      fields: const [FieldSpec('team', 'Team')],
      values: {'team': teams.length == 1 ? teams.single : ''},
      onClose: closeSide,
      onSave: (v) => c.assignTeam(ids, v['team'] ?? ''),
    );
  }

  bool matches(Player p) {
    final q = search.text.trim().toLowerCase();
    return q.isEmpty ||
        p.name.toLowerCase().contains(q) ||
        p.memberId.contains(q) ||
        p.team.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.standingsOnly ? c.pairingEvent : c.event!;
    final colors = Theme.of(context).colorScheme;
    if (side == _Side.player && !e.players.any((p) => p.id == open)) {
      side = open = null;
    }
    selected.removeWhere((id) => !e.players.any((p) => p.id == id));
    if ((side == _Side.team || side == _Side.selection) && selected.isEmpty) {
      side = restingSide;
    }
    if (side == _Side.ratingReview && refreshDraft == null) side = null;
    final coordinator = Dock.maybeOf(context);
    final visibleSide = coordinator == null || coordinator.id == panelOwner
        ? side
        : null;
    final panelWidget = switch (visibleSide) {
      _Side.player => PlayerPanel(
        key: panel,
        controller: c,
        player: e.player(open!),
        focusField: openFocus,
        ratingReview: widget.standingsOnly ? null : refreshDraft,
        onBackToReview: () => showSide(_Side.ratingReview),
        onRemoved: showDone,
        onClose: closeSide,
      ),
      _Side.add => PlayerPanel(
        key: panel,
        controller: c,
        sectionId: widget.sectionId,
        onClose: closeSide,
      ),
      _Side.paste => PasteRosterPanel(
        controller: c,
        onClose: closeSide,
        onImported: imported,
      ),
      _Side.team => teamPanel(),
      _Side.newSection => NewSectionPanel(
        controller: c,
        ticked: {...selected},
        onCreated: sectionsCreated,
        onClose: closeSide,
      ),
      _Side.selection => _selectionPanel(context),
      _Side.ratingReview => RatingReviewPanel(
        draft: refreshDraft!,
        onClose: () => showSide(selected.isEmpty ? null : _Side.selection),
        onConfirm: () => confirmRatings(refreshDraft!),
        onOpenPlayer: openPlayer,
        onAddId: (id) => openPlayer(id, focus: 'memberId'),
      ),
      _Side.done => _donePanel(context),
      null => null,
    };
    if (e.players.isEmpty && !widget.standingsOnly) {
      return _detailsLayout(panel: panelWidget, child: _welcome(context));
    }
    selected.removeWhere((id) => !e.players.any((p) => p.id == id));
    // Roster setup stays separate from the crosstable on the Pairings page.
    final started =
        widget.standingsOnly &&
        e.sections.any(
          (s) =>
              s.rounds.isNotEmpty &&
              (widget.sectionId == null || s.id == widget.sectionId),
        );
    final ranked = started;
    final tables = <String, Map<String, Standing>>{
      for (final s in e.sections)
        if (s.rounds.isNotEmpty)
          s.id: {for (final row in standings(e, s)) row.player.id: row},
    };
    final numbers = <String, int>{};
    List<Player> ordered(Section s) {
      final table = tables[s.id];
      final players = ranked && table != null
          ? [
              for (final row in table.values) row.player,
              for (final id in s.players)
                if (!table.containsKey(id)) e.player(id),
            ]
          : s.players.map(e.player).toList();
      if (entryOrder case final frozen?) {
        players.sort(
          (a, b) => frozen.indexOf(a.id).compareTo(frozen.indexOf(b.id)),
        );
      }
      // Number the full section before filtering so searches preserve positions.
      for (final (i, player) in players.indexed) {
        numbers[player.id] = i + 1;
      }
      return players.where(matches).toList();
    }

    final groups =
        <(Section?, List<Player>)>[
              for (final s in e.sections)
                if (widget.sectionId == null || s.id == widget.sectionId)
                  (s, ordered(s)),
              if (widget.sectionId == null)
                (
                  null,
                  e.players
                      .where((p) => e.sectionOf(p.id) == null && matches(p))
                      .toList()
                    ..sort((a, b) => b.rating.compareTo(a.rating)),
                ),
            ]
            .where(
              (g) => g.$2.isNotEmpty || (g.$1 != null && search.text.isEmpty),
            )
            .toList();
    if (entryOrder case final frozen?) {
      for (final (_, players) in groups) {
        players.sort(
          (a, b) => frozen.indexOf(a.id).compareTo(frozen.indexOf(b.id)),
        );
      }
    }
    final shown = groups.fold(0, (int n, g) => n + g.$2.length);
    rounds = !widget.standingsOnly
        ? 0
        : groups
              .map((g) => g.$1?.plannedRounds ?? 0)
              .fold(0, (int a, b) => a > b ? a : b);
    order = [for (final g in groups) ...g.$2];
    final items = <Widget>[
      for (final (s, players) in groups) ...[
        if (!widget.standingsOnly || widget.sectionId == null)
          _groupHeader(context, s, players),
        if (players.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Text(
              'No players. Tick players below and move them here.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
        for (final p in players)
          _row(
            context,
            s == null ? '' : '${numbers[p.id]}',
            p,
            s,
            rounds,
            s == null ? null : tables[s.id]?[p.id],
            scores: started,
          ),
      ],
    ];
    scores = started;
    final width =
        (widget.onPlayer != null ? 0 : _check) +
        _number +
        (widget.standingsOnly ? 160 : _name) +
        (widget.standingsOnly ? 0 : _rating) +
        (refreshDraft != null ? _proposal + _uscfName : 0) +
        (showRatingPreview ? _preview : 0) +
        (!widget.standingsOnly ? _membership + _note : 0) +
        (showsIds ? _id : 0) +
        rounds * _round +
        (started ? _points : 0) +
        28;
    if (widget.standingsOnly) {
      final heading = PaneHeading(
        child: Text(
          'Crosstable',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      );
      final toolbar = Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SearchField(
              key: const ValueKey('player-search'),
              controller: search,
              onChanged: () => setState(() {}),
              onSubmitted: () {
                final first = order.firstOrNull;
                if (first != null) openPlayer(first.id);
              },
            ),
            if (e.sections.isNotEmpty)
              IconButton(
                key: const ValueKey('print-standings'),
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                tooltip: ranked ? 'Print standings' : 'Print player list',
                onPressed: () => showPrint(
                  context,
                  c.event!,
                  sectionId: widget.sectionId,
                  kind: ranked ? ReportKind.standings : ReportKind.sections,
                ),
                icon: const Icon(Icons.print_outlined, size: 18),
              ),
          ],
        ),
      );
      final table = _table(context, items, width);
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
      child: LayoutBuilder(
        builder: (context, layout) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    layout.maxHeight *
                    (MediaQuery.textScalerOf(context).scale(14) > 21
                        ? 0.3
                        : 0.4),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final searchBox = SearchField(
                            key: const ValueKey('player-search'),
                            controller: search,
                            width: math.min(
                              220,
                              constraints.maxWidth /
                                  MediaQuery.textScalerOf(context).scale(1),
                            ),
                            onChanged: () => setState(() {}),
                            onSubmitted: () {
                              final first = order.firstOrNull;
                              if (first != null) openPlayer(first.id);
                            },
                          );
                          if (widget.standingsOnly) return searchBox;
                          final actions = Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => showSide(_Side.add),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add player'),
                              ),
                              if (widget.onRefreshRatings != null)
                                OutlinedButton(
                                  key: const ValueKey('refresh-uscf'),
                                  onPressed: refreshDraft == null
                                      ? widget.onRefreshRatings
                                      : () => showSide(_Side.ratingReview),
                                  child: const Text('Refresh from USCF'),
                                ),
                              _playerTools(context),
                            ],
                          );
                          return Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [searchBox, actions],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final standingsPane = Column(
                    key: const ValueKey('standings-pane'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              widget.standingsOnly
                                  ? 'Crosstable'
                                  : '$shown ${shown == 1 ? 'player' : 'players'}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (e.sections.isNotEmpty)
                              OutlinedButton.icon(
                                key: const ValueKey('print-standings'),
                                onPressed: () => showPrint(
                                  context,
                                  e,
                                  sectionId: widget.sectionId,
                                  kind: ranked
                                      ? ReportKind.standings
                                      : ReportKind.sections,
                                ),
                                icon: const Icon(
                                  Icons.print_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  ranked
                                      ? 'Print standings'
                                      : 'Print player list',
                                ),
                              ),
                          ],
                        ),
                      ),
                      Flexible(child: _table(context, items, width)),
                    ],
                  );
                  return standingsPane;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table(BuildContext context, List<Widget> items, double width) {
    final colors = Theme.of(context).colorScheme;
    return items.isEmpty
        ? const EmptyState(
            icon: Icons.search_off,
            title: 'No matches',
            body: 'Try a different name or US Chess ID.',
          )
        : Padding(
            padding: widget.standingsOnly
                ? const EdgeInsets.fromLTRB(12, 4, 12, 12)
                : const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final minimum = width * scale;
                final available = constraints.maxWidth.clamp(0.0, 536 * scale);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    // Match the boards in Pairings; keep the roster compact.
                    width: widget.standingsOnly && available > minimum
                        ? available
                        : minimum,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLowest,
                        border: Border.all(color: colors.outlineVariant),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _columns(context, rounds),
                          if (!constraints.hasBoundedHeight)
                            ...items
                          else
                            Flexible(
                              child: ListView(
                                shrinkWrap: true,
                                controller: scroll,
                                children: items,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
  }

  Widget _playerTools(BuildContext context) => MenuAnchor(
    builder: (context, menu, child) => OutlinedButton.icon(
      key: const ValueKey('player-tools'),
      icon: const Icon(Icons.expand_more, size: 18),
      iconAlignment: IconAlignment.end,
      label: const Text('Player tools'),
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
    ),
    menuChildren: [
      if (widget.onRefreshRoster != null)
        MenuItemButton(
          key: const ValueKey('update-event'),
          leadingIcon: const Icon(Icons.sync),
          onPressed: widget.onRefreshRoster,
          child: const Text('Refresh from URL'),
        ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.upload_file_outlined),
        onPressed: () => importFile(),
        child: const Text('Import file…'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.content_copy),
        onPressed: () => showSide(_Side.paste),
        child: const Text('Paste'),
      ),
      const Divider(),
      CheckboxMenuButton(
        key: const ValueKey('show-rating-preview'),
        value: showRatingPreview,
        onChanged: (value) =>
            setState(() => showRatingPreview = value ?? false),
        child: const Text('Show rating estimates'),
      ),
      CheckboxMenuButton(
        value: showIds,
        onChanged: (v) => setState(() => showIds = v!),
        child: const Text('Show US Chess IDs'),
      ),
    ],
  );

  Widget _welcome(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add your players',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.onRefreshRoster != null)
                OutlinedButton.icon(
                  key: const ValueKey('add-from-url'),
                  onPressed: widget.onRefreshRoster,
                  icon: const Icon(Icons.add_link, size: 18),
                  label: const Text('Add from URL'),
                ),
              OutlinedButton.icon(
                onPressed: () => importFile(),
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Import file…'),
              ),
              OutlinedButton.icon(
                onPressed: () => showSide(_Side.paste),
                icon: const Icon(Icons.content_copy, size: 18),
                label: const Text('Paste'),
              ),
              OutlinedButton.icon(
                onPressed: () => showSide(_Side.add),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add one player'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  /// Two ticked players can exchange sections only when a quad or round
  /// robin is involved and neither section is paired; a Swiss uses Move.
  bool canSwapPair(Event e) {
    final a = e.sectionOf(selected.first), b = e.sectionOf(selected.last);
    return a != null && b != null && swapAllowed(a, b);
  }

  /// Bulk actions for the ticked players, in the right-hand column so the
  /// table never moves when a box is ticked.
  Widget _selectionPanel(BuildContext context) {
    final e = c.event!, colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    final ids = selected.toList();
    final names = ids.map((id) => e.player(id).name).toList();
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
    return SidePanel(
      key: const ValueKey('selection-panel'),
      title: '${ids.length} ${ids.length == 1 ? 'player' : 'players'} selected',
      onClose: clearSelection,
      footer: [
        OutlinedButton(
          key: const ValueKey('clear-selection'),
          onPressed: clearSelection,
          child: const Text('Clear selection'),
        ),
      ],
      children: [
        Text(
          names.length <= 6
              ? names.join(', ')
              : '${names.take(5).join(', ')} and ${names.length - 5} more',
          style: muted,
        ),
        ...[
          heading(e.sections.isEmpty ? 'Put in a section' : 'Move to section'),
          if (moveTo != null) ...[
            Text(
              'Move to ${e.sections.firstWhere((s) => s.id == moveTo).name}?',
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('move-reason'),
              controller: moveReason,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason'),
              onSubmitted: (_) => confirmMove(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(onPressed: confirmMove, child: const Text('Move')),
                TextButton(
                  onPressed: () => setState(() => moveTo = null),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ] else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in e.sections)
                  ActionChip(
                    chipAnimationStyle: noChipAnimation,
                    key: ValueKey('move-to-${s.id}'),
                    tooltip:
                        '${s.name} has ${s.players.length} '
                        '${s.players.length == 1 ? 'player' : 'players'}',
                    label: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: s.name),
                          TextSpan(
                            text: '  ${s.players.length}',
                            style: muted.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    onPressed: selected.every(s.players.contains)
                        ? null
                        : () => moveSelected(s.id),
                  ),
                ActionChip(
                  chipAnimationStyle: noChipAnimation,
                  key: const ValueKey('selection-new-section'),
                  avatar: Icon(Icons.add, size: 18, color: colors.onSurface),
                  label: const Text('New section…'),
                  onPressed: () => showSide(_Side.newSection),
                ),
              ],
            ),
        ],
        heading('Actions'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (selected.length == 2 && canSwapPair(e))
              OutlinedButton(
                onPressed: () {
                  if (!swapping) {
                    setState(() {
                      swapping = true;
                      moveRevision = e.revision;
                    });
                    return;
                  }
                  try {
                    c.swapPlayers(selected.first, selected.last, moveRevision!);
                    clearSelection();
                  } catch (error) {
                    showFailure(context, error);
                    setState(() => swapping = false);
                  }
                },
                child: Text(
                  swapping
                      ? 'Confirm swap: ${e.player(selected.first).name} ↔ ${e.player(selected.last).name}'
                      : 'Swap sections',
                ),
              ),
            if (selected.length == 2)
              OutlinedButton(
                onPressed: () {
                  try {
                    c.avoidPair(selected.first, selected.last, true);
                    clearSelection();
                  } catch (e) {
                    showFailure(context, e);
                  }
                },
                child: const Text('Do not pair together'),
              ),
            OutlinedButton.icon(
              onPressed: () => showSide(_Side.team),
              icon: const Icon(Icons.group_outlined, size: 18),
              label: const Text('Assign team'),
            ),
            for (final action in statusActions(e, ids))
              OutlinedButton(
                key: ValueKey('selection-${action.name}'),
                onPressed: () => applyStatusTo(action, ids),
                child: Text(statusLabel(e, action, ids)),
              ),
          ],
        ),
      ],
    );
  }

  /// Confirms a finished import or rating update in place, with Undo.
  Widget _donePanel(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canUndo = c.graph.head == doneHead;
    return SidePanel(
      key: const ValueKey('done-panel'),
      title: doneTitle ?? 'Saved',
      onClose: closeSide,
      footer: [
        Row(
          children: [
            if (canUndo)
              OutlinedButton.icon(
                key: const ValueKey('done-undo'),
                onPressed: () {
                  try {
                    c.undo();
                    closeSide();
                  } catch (error) {
                    showFailure(context, error);
                  }
                },
                icon: const Icon(Icons.undo),
                label: const Text('Undo'),
              ),
            const Spacer(),
            OutlinedButton(
              key: const ValueKey('done-close'),
              autofocus: true,
              onPressed: closeSide,
              child: const Text('Done'),
            ),
          ],
        ),
      ],
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 20,
                color: colors.onSurface,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(doneMessage ?? '')),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          canUndo
              ? 'Undo puts everything back as it was.'
              : 'Later changes were made. Undo is in History.',
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  double _columnWidth(BuildContext context, double width) =>
      width * MediaQuery.textScalerOf(context).scale(14) / 14;

  Widget _columns(BuildContext context, int rounds) {
    final colors = Theme.of(context).colorScheme;
    Widget cell(double width, String text, {bool center = false}) => SizedBox(
      width: _columnWidth(context, width),
      child: Text(
        text,
        textAlign: center ? TextAlign.center : null,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return Container(
      key: const ValueKey('player-column-header'),
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
        child: Row(
          children: [
            if (!widget.standingsOnly)
              SizedBox(width: _columnWidth(context, _check)),
            cell(_number, '#'),
            const Expanded(child: Text('Name')),
            if (showsIds) cell(_id, 'USCF ID'),
            if (!widget.standingsOnly)
              cell(_rating, refreshDraft == null ? 'Rating' : 'Entered'),
            if (refreshDraft case final draft?) ...[
              cell(_proposal, proposedHeading(draft)),
              cell(_uscfName, 'USCF name'),
            ],
            if (showRatingPreview) cell(_preview, 'Est. regular (Δ)'),
            if (!widget.standingsOnly) ...[
              cell(_membership, 'USCF expires'),
              cell(_note, 'Registration note'),
            ],
            for (var r = 1; r <= rounds; r++) cell(_round, 'R$r', center: true),
            if (scores) ...[cell(_points, 'Pts', center: true)],
          ],
        ),
      ),
    );
  }

  Widget _groupHeader(BuildContext context, Section? s, List<Player> players) {
    final colors = Theme.of(context).colorScheme;
    final ids = players.map((p) => p.id).toSet();
    final picked = ids.where(selected.contains).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant),
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          if (widget.onPlayer == null)
            SizedBox(
              width: _columnWidth(context, _check),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PlainCheckbox(
                  label:
                      'Select all visible players in ${s?.name ?? 'unassigned players'}',
                  tristate: true,
                  value: ids.isEmpty || picked == 0
                      ? false
                      : picked == ids.length
                      ? true
                      : null,
                  onChanged: ids.isEmpty
                      ? null
                      : (_) => tick(ids, picked != ids.length),
                ),
              ),
            ),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: s?.name ?? 'Not in a section',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (!widget.standingsOnly)
                    TextSpan(
                      text:
                          '   ${['${s?.players.length ?? players.length} players', if (widget.standingsOnly && s != null) pairingFormat(s) == s.format ? formatName(s.format) : 'Quad · will pair as a small Swiss', if (widget.standingsOnly && s != null) boardRange(s), if (widget.standingsOnly && s != null && s.rounds.isNotEmpty) 'round ${s.rounds.length} of ${s.plannedRounds}'].join(' · ')}',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// A posted round's bye mark, and a tooltip naming each opponent.
  (String, String) _played(Section s, int number, String pid) {
    final e = c.event!;
    final round = s.rounds.where((r) => r.number == number).firstOrNull;
    if (round == null) return ('', '');
    final bye = round.byes.where((b) => b.player == pid).firstOrNull;
    if (bye != null) {
      return (byeMark(bye.points), 'Round $number: ${bye.reason}');
    }
    final games = round.games
        .where((g) => g.white == pid || g.black == pid)
        .toList();
    if (games.isEmpty) return ('', '');
    String against(Game g) {
      final white = g.white == pid;
      final o = e.player(white ? g.black : g.white);
      final result = switch (scoreMark(g.outcome, white: white)) {
        _ when !g.outcome.resolved => '',
        '1' => '1 (won) ',
        '0' => '0 (lost) ',
        '½' => '½ (drew) ',
        'X' => 'X (won by forfeit) ',
        _ => 'F (forfeited) ',
      };
      final pending = g.outcome.resolved
          ? ''
          : g.outcome == Outcome.unreported
          ? ', no result yet'
          : ', ${g.outcome.label.toLowerCase()}';
      return '${result}vs ${o.name} (${ratingText(o.rating)}) as ${white ? 'White' : 'Black'}$pending';
    }

    final tip = 'Round $number: ${games.map(against).join('; ')}';
    // Played games show score boxes; only a bye needs a mark.
    return ('', tip);
  }

  Widget _roundCell(BuildContext context, Player p, Section? s, int r) {
    final colors = Theme.of(context).colorScheme;
    if (s != null && r > s.plannedRounds) {
      return SizedBox(width: _columnWidth(context, _round));
    }
    final played = s != null && r <= s.rounds.length;
    final bye = played ? null : p.byes[r];
    final (mark, tip) = played
        ? _played(s, r, p.id)
        : bye != null
        ? (byeMark(bye), 'Round $r: ${halves(bye)}-point bye requested')
        : ('—', 'Round $r: not paired yet.');
    final games = played
        ? s.rounds
              .firstWhere((x) => x.number == r)
              .games
              .where((g) => g.white == p.id || g.black == p.id)
              .toList()
        : <Game>[];
    return SizedBox(
      key: ValueKey('round-${p.id}-$r'),
      width: _columnWidth(context, _round),
      child: games.isEmpty
          ? Tooltip(
              message: tip,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  mark,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            )
          : Row(
              children: [
                for (final g in games)
                  Expanded(
                    child: Focus(
                      focusNode: standingFocus(g, p.id),
                      onKeyEvent: (_, event) => standingKey(p, s!, r, g, event),
                      onFocusChange: (hasFocus) {
                        if (!mounted) return;
                        if (!hasFocus) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted &&
                                !enteringResult &&
                                !resultFocus.values.any(
                                  (node) => node.hasFocus,
                                )) {
                              setState(() => entryOrder = null);
                            }
                          });
                        }
                        if (hasFocus) {
                          entryOrder ??= order.map((p) => p.id).toList();
                          activeResult = '${g.id}-${p.id}';
                        }
                        setState(() {});
                      },
                      child: Semantics(
                        label:
                            '${p.name}, round $r, ${games.length > 1 ? 'game ${g.leg}, ' : ''}$tip. $resultKeyHint',
                        child: Tooltip(
                          message: tip,
                          child: GestureDetector(
                            key: ValueKey('standing-score-${g.id}-${p.id}'),
                            onTap: () => focusStanding(g, p.id),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: standingFocus(g, p.id).hasFocus
                                      ? colors.primary
                                      : colors.outlineVariant,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                scoreMark(
                                      g.outcome,
                                      white: g.white == p.id,
                                    ).isEmpty
                                    ? '—'
                                    : scoreMark(
                                        g.outcome,
                                        white: g.white == p.id,
                                      ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _row(
    BuildContext context,
    String number,
    Player p,
    Section? s,
    int rounds,
    Standing? standing, {
    required bool scores,
  }) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(color: colors.onSurfaceVariant);
    Widget cell(double width, String text, [TextStyle? style]) => SizedBox(
      width: _columnWidth(context, width),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
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
    final ticked = selected.contains(p.id);
    return ContextMenuKeys(
      onMenu: menu,
      child: CallbackShortcuts(
        bindings: {
          if (!widget.standingsOnly)
            const SingleActivator(LogicalKeyboardKey.delete): () =>
                removeFromKey(p.id),
        },
        child: InkWell(
          key: ValueKey('player-${p.id}'),
          onSecondaryTapDown: (details) => menu(details.globalPosition),
          onTap: () => openPlayer(p.id),
          child: Container(
            constraints: widget.standingsOnly
                ? const BoxConstraints(minHeight: 32)
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: open == p.id
                  ? colors.primary.withValues(alpha: 0.1)
                  : ticked
                  ? colors.surfaceContainerHigh
                  : null,
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (widget.onPlayer == null)
                      SizedBox(
                        width: _columnWidth(context, _check),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: PlainCheckbox(
                            label: 'Select ${p.name}',
                            value: ticked,
                            onChanged: (v) => tickRow(p.id, v == true),
                          ),
                        ),
                      ),
                    KeyedSubtree(
                      key: ValueKey('number-${p.id}'),
                      child: cell(_number, number, muted),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: p.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: p.withdrawn
                                    ? colors.onSurfaceVariant
                                    : null,
                                decoration: p.withdrawn
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (p.team.isNotEmpty)
                              TextSpan(
                                text: '  · ${p.team}',
                                style: muted.copyWith(fontSize: 12),
                              ),
                            if (p.withdrawn)
                              TextSpan(
                                text: '  withdrawn',
                                style: muted.copyWith(fontSize: 12),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (showsIds)
                      cell(
                        _id,
                        p.memberId.isEmpty ? '—' : p.memberId,
                        muted.copyWith(fontFamily: 'SourceCodePro'),
                      ),
                    if (!widget.standingsOnly)
                      cell(
                        _rating,
                        ratingText(p.rating),
                        const TextStyle(fontFamily: 'SourceCodePro'),
                      ),
                    if (refreshDraft case final draft?) ...[
                      _proposedRatingCell(context, p, draft),
                      _uscfNameCell(context, p, draft),
                    ],
                    if (showRatingPreview) _ratingPreviewCell(context, p, s),
                    if (!widget.standingsOnly)
                      SizedBox(
                        width: _columnWidth(context, _membership),
                        child: MembershipCell(
                          player: p,
                          eventDate: c.event!.lastDate,
                        ),
                      ),
                    if (!widget.standingsOnly)
                      Tooltip(
                        message: p.registrationNote,
                        child: cell(
                          _note,
                          p.registrationNote.isEmpty ? '—' : p.registrationNote,
                          muted,
                        ),
                      ),
                    for (var r = 1; r <= rounds; r++)
                      _roundCell(context, p, s, r),
                    if (scores) ...[
                      SizedBox(
                        width: _columnWidth(context, _points),
                        child: Text(
                          standing == null ? '' : halves(standing.points),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The USCF rating and its change, ticked to include it in the update.
  Widget _proposedRatingCell(
    BuildContext context,
    Player p,
    RatingRefresh draft,
  ) {
    final problem = draft.problem(p);
    final proposed = draft.proposed(p);
    final highlight = problem == null && draft.largeChange(p);
    final colors = Theme.of(context).colorScheme;
    final m = draft.observations[p.id];
    // Numbers wherever US Chess gave an answer: unrated reads UNR, an
    // unchanged rating ±0. Other problems keep their reason.
    final unrated = draft.unratedAtUscf(p);
    final numbers =
        proposed != null &&
        proposed > 0 &&
        (problem == null || draft.upToDate(p));
    final shown = unrated
        ? 'UNR'
        : numbers
        ? '$proposed'
        : null;
    final change = unrated
        // The entered rating stays; US Chess never replaces it with UNR.
        ? (p.rating == 0 ? '±0' : 'keep ${p.rating}')
        : numbers
        ? ratingChange(draft, p)
        : null;
    return Tooltip(
      message: [
        ?problem,
        if (highlight)
          p.rating == 0
              ? 'Highlighted: first rating. Entered as unrated (UNR).'
              : 'Highlighted: large rating change, more than 50 points.',
        if (m != null) 'Supplement ${m.supplementDate ?? 'date unavailable'}',
      ].join('\n'),
      child: Container(
        key: ValueKey('rating-proposal-${p.id}'),
        width: _columnWidth(context, _proposal) - 12,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        color: highlight ? colors.tertiary.withValues(alpha: 0.16) : null,
        child: Row(
          children: [
            PlainCheckbox(
              key: ValueKey('approve-rating-${p.id}'),
              label: 'Apply USCF rating for ${p.name}',
              value: problem == null && draft.selected.contains(p.id),
              onChanged: draft.busy || problem != null
                  ? null
                  : (value) => draft.select(p, value == true),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                draft.missingId(p)
                    ? TextSpan(
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(
                              Icons.error_outline,
                              size: 16,
                              color: attentionColor(colors),
                            ),
                          ),
                          TextSpan(
                            text: ' No USCF ID',
                            style: TextStyle(
                              color: attentionColor(colors),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : shown == null
                    ? TextSpan(
                        // The first sentence fits; the tooltip has the rest.
                        text: problem?.split('. ').first ?? '—',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      )
                    : TextSpan(
                        children: [
                          TextSpan(
                            text: shown,
                            style: TextStyle(
                              fontFamily: 'SourceCodePro',
                              fontWeight: highlight
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: problem == null
                                  ? null
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                          if (change != null)
                            TextSpan(
                              text: '  $change',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: highlight
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: highlight
                                    ? colors.onSurface
                                    : colors.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                        ],
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The name US Chess has for the ID, flagged when it looks like somebody
  /// else, so a mistyped ID is caught before its rating is used.
  Widget _uscfNameCell(BuildContext context, Player p, RatingRefresh draft) {
    final colors = Theme.of(context).colorScheme;
    final m = draft.observations[p.id];
    final mismatch = draft.nameMismatch(p);
    final width = _columnWidth(context, _uscfName);
    if (m == null || m.name.trim().isEmpty) {
      return SizedBox(
        width: width,
        child: Text('—', style: TextStyle(color: colors.onSurfaceVariant)),
      );
    }
    if (!mismatch) {
      return SizedBox(
        key: ValueKey('uscf-name-${p.id}'),
        width: width,
        child: Text(
          m.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      );
    }
    final attention = attentionColor(colors);
    return Tooltip(
      message:
          'Entered as ${p.name}. US Chess has ${m.name} for ${p.memberId}. '
          'Check the ID before updating this rating.',
      child: Semantics(
        label: 'USCF name ${m.name} differs from the entered name',
        excludeSemantics: true,
        child: SizedBox(
          key: ValueKey('uscf-name-${p.id}'),
          width: width,
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: attention),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: attention,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ratingPreviewCell(
    BuildContext context,
    Player player,
    Section? section,
  ) {
    final preview = previewRating(c.event!, section, player);
    final change = preview.change;
    return SizedBox(
      width: _columnWidth(context, _preview),
      child: Tooltip(
        message:
            preview.reason ??
            'Approximate regular rating from ${preview.games} completed played games, using starting opponent ratings.',
        child: Text(
          preview.rating == null
              ? '—'
              : '≈${preview.rating} (${change! > 0 ? '+' : ''}$change)',
          key: ValueKey('rating-preview-${player.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'SourceCodePro'),
        ),
      ),
    );
  }
}

String formatName(Format f) => switch (f) {
  Format.swiss => 'Swiss',
  Format.quad => 'Quad',
  Format.roundRobin => 'Round robin',
};

/// Edits one player beside the table, so the list stays in view. Field edits
/// save on Enter, on Save, when another player is opened, or when the panel
/// closes. Byes, section and withdrawal apply at once.
enum _Side {
  newSection,
  player,
  add,
  paste,
  team,
  selection,
  ratingReview,
  done,
}
