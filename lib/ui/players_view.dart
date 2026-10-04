import 'result_keys.dart';
import 'player_actions.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/failures.dart';
import '../application/tournament_controller.dart';
import 'rating_refresh.dart';
import '../domain/model.dart';
import '../domain/membership.dart';
import 'membership_style.dart';
import '../domain/pairing.dart';
import '../domain/standings.dart';
import '../domain/rating_preview.dart';
import '../domain/us_chess.dart';
import '../infrastructure/roster_import.dart';
import 'dialogs.dart';
import 'update_panels.dart' show RatingsRefreshPanel;
import 'result_correction_dialog.dart';
import 'drafts.dart';
import 'roster_import_panel.dart';
import 'panels.dart' show FieldsPanel, Dock, showPrint;
import '../infrastructure/reports.dart' show ReportKind;
import 'theme.dart';
import 'identity_review.dart';
import 'member_identity_lookup.dart';
import 'results_view.dart' show scoreMark;
import '../infrastructure/ratings_api.dart';

/// Imports roster text and returns a one-line summary.
String importRoster(TournamentController c, String source) {
  return importRosterRows(c, parseRoster(source));
}

/// Commits the same interpreted rows that were reviewed in the preview.
String importRosterRows(TournamentController c, List<ImportRow> rows) {
  final valid = rows.where((r) => r.player != null).toList();
  if (valid.isEmpty) {
    throw const TournamentException('No players found.');
  }
  final skipped = c.importPlayers(valid.map((r) => r.player!).toList());
  final bad = rows.where((r) => r.error != null).map((r) => r.line).toList();
  return [
    'Imported ${valid.length - skipped} players',
    if (skipped > 0) '$skipped already in the event',
    if (bad.isNotEmpty) '${bad.length} unreadable (line ${bad.join(', ')})',
  ].join(' · ');
}

/// A rating as typed and shown: UNR for unrated.
String ratingText(int rating) => rating == 0 ? 'UNR' : '$rating';

/// Reads a typed rating. Blank, UNR and "unrated" mean unrated (0).
int? parseRating(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty || t == 'unr' || t == 'unr.' || t == 'unrated') return 0;
  final n = int.tryParse(t);
  return n == null || n < 0 ? null : n;
}

/// ½-point units as a short label: 0, ½, 1, 1½ …
String halves(int n) => n == 1
    ? '½'
    : n.isOdd
    ? '${n ~/ 2}½'
    : '${n ~/ 2}';

/// First and last board a section uses, e.g. "boards 3–4".
String boardRange(Section s) {
  final count = (s.players.length + 1) ~/ 2;
  if (count <= 1) return 'board ${s.boardStart}';
  return 'boards ${s.boardStart}–${s.boardStart + count - 1}';
}

class PlayersView extends StatefulWidget {
  const PlayersView({
    required this.controller,
    this.sectionId,
    this.onLookup,
    this.onRefreshRoster,
    this.onRefreshRatings,
    this.onAddSections,
    this.ratingRefresh,
    this.roundAction,
    this.standingsOnly = false,
    this.onPlayer,
    this.standingsLayout,
    super.key,
  });
  final TournamentController controller;
  final String? sectionId;
  final VoidCallback? onLookup;
  final VoidCallback? onRefreshRoster, onRefreshRatings;
  final VoidCallback? onAddSections;
  final RatingRefresh? ratingRefresh;
  final Widget? roundAction;
  final bool standingsOnly;

  /// Embedded crosstables open details in their parent workspace.
  final ValueChanged<String>? onPlayer;

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

  /// What the side panel shows: a player, a new player, or pasting.
  _Side? side;
  String? importSource, importFilename;
  String? completion;
  int? completionRevision;

  void showCompletion(String message) {
    setState(() {
      completion = message;
      completionRevision = c.event!.revision;
    });
  }

  void imported(String summary) {
    showSide(null);
    showCompletion(summary);
  }

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
  bool enteringResult = false, resultForfeit = false;

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
    if (key == LogicalKeyboardKey.keyF) {
      setState(() => resultForfeit = true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() => resultForfeit = false);
      return KeyEventResult.handled;
    }
    final outcome = resultFromKey(
      event,
      white: game.white == p.id,
      forfeit: resultForfeit,
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
        await reviewResultCorrection(context, c, game.id, outcome: outcome);
        return;
      }
      c.recordResult(game.id, outcome);
      resultForfeit = false;
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
      _membership = 156.0,
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
    if (side == _Side.fileImport) side = null;
    selected.addAll((saved['selected'] as List? ?? []).whereType<String>());
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
    });
  }

  void refreshRatingsView() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant PlayersView oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      setState(() {
        importSource = source;
        importFilename = file.name;
      });
      showSide(_Side.fileImport);
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  void openPlayer(String id) {
    if (widget.onPlayer case final onPlayer?) {
      onPlayer(id);
    } else {
      showSide(_Side.player, id);
    }
  }

  Widget _detailsLayout({required Widget child, Widget? panel}) =>
      widget.onPlayer != null
      ? child
      : PlayerDetailsLayout(expandContent: true, panel: panel, child: child);

  /// Moves the ticked players. Once play has started a reason is asked for
  /// in the selection bar first.
  void moveSelected(String targetId, {String reason = ''}) {
    if (moveTo != targetId) {
      setState(() {
        moveTo = targetId;
        moveRevision = c.event!.revision;
      });
      return;
    }
    try {
      if (moveRevision != null && moveRevision != c.event!.revision) {
        moveTo = null;
        throw const TournamentException(
          'The event changed. Choose the destination and review again.',
        );
      }
      c.movePlayers(selected.toList(), targetId, reason: reason);
      setState(() {
        selected.clear();
        moveTo = null;
      });
      moveReason.clear();
    } catch (e) {
      showFailure(context, e);
    }
  }

  void confirmMove() {
    final reason = moveReason.text.trim();
    moveSelected(moveTo!, reason: reason);
  }

  void withdrawSelected(bool withdrawn) {
    try {
      for (final id in selected.toList()) {
        c.savePlayer(c.event!.player(id).copy(withdrawn: withdrawn));
      }
      setState(selected.clear);
    } catch (e) {
      showFailure(context, e);
    }
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
      description:
          'Use the same name for mixed-doubles partners. Leave blank to remove the team. Team membership does not change individual pairings.',
      fields: const [FieldSpec('team', 'Team name')],
      values: {'team': teams.length == 1 ? teams.single : ''},
      onClose: () => showSide(null),
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
    if (side == _Side.team && selected.isEmpty) side = null;
    final coordinator = Dock.maybeOf(context);
    final visibleSide = coordinator == null || coordinator.id == panelOwner
        ? side
        : null;
    final panelWidget = switch (visibleSide) {
      _Side.player => PlayerPanel(
        key: panel,
        controller: c,
        player: e.player(open!),
        onClose: () => showSide(null),
      ),
      _Side.add => PlayerPanel(
        key: panel,
        controller: c,
        sectionId: widget.sectionId,
        onClose: () => showSide(null),
      ),
      _Side.paste => _PastePanel(
        controller: c,
        onClose: () => showSide(null),
        onImported: imported,
      ),
      _Side.fileImport => RosterImportPanel(
        key: ValueKey((importFilename, importSource)),
        controller: c,
        source: importSource!,
        filename: importFilename!,
        onClose: () => showSide(null),
        onImported: imported,
      ),
      _Side.team => teamPanel(),
      _Side.membership => RatingsRefreshPanel.membership(
        controller: c,
        onClose: () => showSide(null),
      ),
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
    final unassigned = e.players.where((p) => e.sectionOf(p.id) == null).length;
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
        (refreshDraft != null ? 280 : 0) +
        (showRatingPreview ? _preview : 0) +
        (!widget.standingsOnly ? _membership + _note : 0) +
        (showIds && !widget.standingsOnly ? _id : 0) +
        rounds * _round +
        (started ? _points : 0) +
        28;
    if (widget.standingsOnly) {
      final heading = Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
            SizedBox(
              width: 180 * MediaQuery.textScalerOf(context).scale(1),
              child: TextField(
                key: const ValueKey('player-search'),
                controller: search,
                decoration: InputDecoration(
                  labelText: 'Search players',
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: controlHeight,
                  ),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(search.clear),
                        ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  final first = order.firstOrNull;
                  if (first != null) openPlayer(first.id);
                },
              ),
            ),
            IconButton(
              key: const ValueKey('print-standings'),
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              tooltip: ranked ? 'Print standings' : 'Print section sheets',
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
                if (widget.onPlayer == null) _selectionBar(context),
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
                      if (completion != null &&
                          completionRevision == e.revision)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(completion!),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  try {
                                    c.undo();
                                    setState(() => completion = null);
                                  } catch (error) {
                                    showFailure(context, error);
                                  }
                                },
                                child: const Text('Undo'),
                              ),
                              IconButton(
                                tooltip: 'Dismiss confirmation',
                                onPressed: () =>
                                    setState(() => completion = null),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ],
                          ),
                        ),
                      if (refreshDraft case final draft?)
                        _ratingReviewToolbar(context, draft),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final searchWidth =
                              220 * MediaQuery.textScalerOf(context).scale(1);
                          final searchBox = SizedBox(
                            width: constraints.maxWidth < searchWidth
                                ? constraints.maxWidth
                                : searchWidth,
                            child: TextField(
                              key: const ValueKey('player-search'),
                              controller: search,
                              decoration: InputDecoration(
                                labelText: 'Search players',
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.never,
                                prefixIcon: const Icon(Icons.search, size: 20),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: controlHeight,
                                ),
                                suffixIconConstraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: controlHeight,
                                ),
                                suffixIcon: search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        icon: const Icon(Icons.close, size: 18),
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              width: 32,
                                              height: 32,
                                            ),
                                        onPressed: () => setState(search.clear),
                                      ),
                              ),
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) {
                                final first = order.firstOrNull;
                                if (first != null) openPlayer(first.id);
                              },
                            ),
                          );
                          if (widget.standingsOnly) return searchBox;
                          final actions = Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (widget.onLookup != null)
                                IconButton(
                                  tooltip: 'Find player (Ctrl+L)',
                                  onPressed: widget.onLookup,
                                  icon: const Icon(
                                    Icons.person_search_outlined,
                                    size: 20,
                                  ),
                                ),
                              FilledButton.icon(
                                onPressed: () => showSide(_Side.add),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add player'),
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
            if (!widget.standingsOnly &&
                unassigned > 0 &&
                widget.onAddSections != null)
              _banner(
                context,
                '$unassigned ${unassigned == 1 ? 'player is' : 'players are'} not in a section yet.',
                FilledButton(
                  onPressed: widget.onAddSections,
                  child: const Text('Create sections…'),
                ),
              ),
            if (widget.onPlayer == null) _selectionBar(context),
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
                              icon: const Icon(Icons.print_outlined, size: 18),
                              label: Text(
                                ranked
                                    ? 'Print standings'
                                    : 'Print section sheets',
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
      if (widget.onRefreshRatings != null)
        MenuItemButton(
          key: const ValueKey('refresh-uscf'),
          leadingIcon: const Icon(Icons.refresh),
          onPressed: c.event!.players.isEmpty ? null : widget.onRefreshRatings,
          child: const Text('Refresh from USCF'),
        ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.verified_user_outlined),
        onPressed: c.event!.players.isEmpty
            ? null
            : () => showSide(_Side.membership),
        child: const Text('Check memberships'),
      ),
      const Divider(),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add your players',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _playerTools(context),
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
    ),
  );

  Widget _banner(BuildContext context, String text, Widget action) => Container(
    margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [action, Text(text)],
    ),
  );

  /// Bulk actions appear only while players are selected.
  Widget _selectionBar(BuildContext context) {
    if (selected.isEmpty) return const SizedBox.shrink();
    final e = c.event!, colors = Theme.of(context).colorScheme;
    final allWithdrawn = selected.every((id) => e.player(id).withdrawn);
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(minHeight: controlHeight + 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: selected.isNotEmpty && moveTo != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Move ${selected.map((id) => e.player(id).name).join(', ')} to ${e.sections.firstWhere((s) => s.id == moveTo).name}?',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 260,
                      child: TextField(
                        key: const ValueKey('move-reason'),
                        controller: moveReason,
                        decoration: const InputDecoration(
                          labelText: 'Reason (required after play)',
                        ),
                        onSubmitted: (_) => confirmMove(),
                      ),
                    ),
                    FilledButton(
                      onPressed: confirmMove,
                      child: const Text('Move'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => moveTo = null),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            )
          : selected.isEmpty
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tick players to move or withdraw them',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  Text(
                    '${selected.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (e.sections.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    const Text('Move to'),
                    for (final s in e.sections)
                      ActionChip(
                        chipAnimationStyle: noChipAnimation,
                        key: ValueKey('move-to-${s.id}'),
                        label: Text(s.name),
                        onPressed: selected.every(s.players.contains)
                            ? null
                            : () => moveSelected(s.id),
                      ),
                  ],
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => showSide(_Side.team),
                    icon: const Icon(Icons.group_outlined, size: 18),
                    label: const Text('Assign team'),
                  ),
                  if (selected.length == 2)
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
                          c.swapPlayers(
                            selected.first,
                            selected.last,
                            moveRevision!,
                          );
                          setState(() {
                            selected.clear();
                            swapping = false;
                          });
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
                          setState(selected.clear);
                        } catch (e) {
                          showFailure(context, e);
                        }
                      },
                      child: const Text('Do not pair together'),
                    ),
                  OutlinedButton(
                    onPressed: () => withdrawSelected(!allWithdrawn),
                    child: Text(allWithdrawn ? 'Reinstate' : 'Withdraw'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      selected.clear();
                      swapping = false;
                    }),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
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
            if (!widget.standingsOnly) cell(_rating, 'Rating'),
            if (showIds && !widget.standingsOnly) cell(_id, 'USCF ID'),
            if (refreshDraft != null) cell(280, 'Proposed USCF rating'),
            if (showRatingPreview) cell(_preview, 'Est. regular (Δ)'),
            if (!widget.standingsOnly) ...[
              cell(_membership, 'USCF expires'),
              cell(_note, 'Note'),
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
                      : (_) => setState(() {
                          if (picked == ids.length) {
                            selected.removeAll(ids);
                          } else {
                            selected.addAll(ids);
                          }
                        }),
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
      return ('B${halves(bye.points)}', 'Round $number: ${bye.reason}');
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
        '1F' => '1F (won by forfeit) ',
        _ => '0F (lost by forfeit) ',
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
        ? (
            'B${halves(bye)}',
            'Round $r: ${halves(bye)}-point bye requested. Edit in player details.',
          )
        : ('—', 'Round $r: not paired. Request byes in player details.');
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
                              setState(() {
                                entryOrder = null;
                                resultForfeit = false;
                              });
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
    return InkWell(
      key: ValueKey('player-${p.id}'),
      onSecondaryTapDown: (details) =>
          showPlayerMenu(context, c, p.id, details.globalPosition),
      onTap: () => openPlayer(p.id),
      onDoubleTap: refreshDraft == null ? null : () => openPlayer(p.id),
      child: Container(
        constraints: widget.standingsOnly
            ? const BoxConstraints(minHeight: 32)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: open == p.id ? colors.primary.withValues(alpha: 0.1) : null,
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
                        value: selected.contains(p.id),
                        onChanged: (v) => setState(
                          () => v! ? selected.add(p.id) : selected.remove(p.id),
                        ),
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
                            color: p.withdrawn ? colors.onSurfaceVariant : null,
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
                if (!widget.standingsOnly)
                  cell(
                    _rating,
                    ratingText(p.rating),
                    const TextStyle(fontFamily: 'SourceCodePro'),
                  ),
                if (showIds && !widget.standingsOnly)
                  cell(
                    _id,
                    p.memberId.isEmpty ? '—' : p.memberId,
                    muted.copyWith(fontFamily: 'SourceCodePro'),
                  ),
                if (refreshDraft case final draft?)
                  _proposedRatingCell(context, p, draft),
                if (showRatingPreview) _ratingPreviewCell(context, p, s),
                if (!widget.standingsOnly)
                  SizedBox(
                    width: _columnWidth(context, _membership),
                    child: _MembershipCell(
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
                for (var r = 1; r <= rounds; r++) _roundCell(context, p, s, r),
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
    );
  }

  Widget _ratingReviewToolbar(BuildContext context, RatingRefresh draft) {
    return Container(
      key: const ValueKey('rating-review'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review USCF ratings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            draft.busy
                ? 'Looking up ratings… ${draft.observations.length + draft.failures.length} checked'
                : 'Found ratings for ${draft.foundCount} players. ${c.event!.players.length - draft.foundCount} missing — see player rows.',
          ),
          const Text(
            'Highlighted cells: Changes over 50 points or unrated → rated. Double-click a player to edit.',
          ),
          if (draft.notice != null) Text(draft.notice!),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: draft.category,
                items: const [
                  DropdownMenuItem(value: 'R', child: Text('Regular')),
                  DropdownMenuItem(value: 'Q', child: Text('Quick')),
                  DropdownMenuItem(value: 'B', child: Text('Blitz')),
                ],
                onChanged: draft.busy
                    ? null
                    : (value) {
                        if (value != null) draft.fetch(ratingCategory: value);
                      },
              ),
              if (draft.busy)
                TextButton(
                  onPressed: draft.stop,
                  child: const Text('Stop lookup'),
                )
              else ...[
                TextButton(
                  onPressed: () => draft.fetch(),
                  child: const Text('Retry refresh'),
                ),
                TextButton(
                  onPressed: () => draft.selectAll(true),
                  child: const Text('Select all'),
                ),
                TextButton(
                  onPressed: () => draft.selectAll(false),
                  child: const Text('Select none'),
                ),
              ],
              FilledButton(
                onPressed: draft.busy || draft.approved.isEmpty
                    ? null
                    : () {
                        try {
                          final count = draft.apply();
                          showCompletion('Updated $count USCF ratings.');
                        } catch (e) {
                          showFailure(context, e);
                        }
                      },
                child: Text('Confirm ${draft.approved.length} rating changes'),
              ),
              TextButton(
                onPressed: draft.discard,
                child: const Text('Keep current ratings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _proposedRatingCell(
    BuildContext context,
    Player p,
    RatingRefresh draft,
  ) {
    final problem = draft.problem(p);
    final proposed = draft.proposed(p);
    final m = draft.observations[p.id];
    final highlight = problem == null && draft.largeChange(p);
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: _columnWidth(context, 280),
      child: Container(
        key: ValueKey('rating-proposal-${p.id}'),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        color: highlight ? colors.tertiary.withValues(alpha: 0.16) : null,
        child: Row(
          children: [
            Checkbox(
              key: ValueKey('approve-rating-${p.id}'),
              semanticLabel: 'Apply USCF rating for ${p.name}',
              value: problem == null && draft.selected.contains(p.id),
              onChanged: draft.busy || problem != null
                  ? null
                  : (value) => draft.select(p, value == true),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (proposed != null && proposed > 0)
                    Text(
                      '${ratingText(p.rating)} → $proposed',
                      style: TextStyle(
                        fontWeight: highlight
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: highlight ? colors.onSurface : null,
                      ),
                    ),
                  if (problem != null)
                    Text(problem, style: const TextStyle(fontSize: 12)),
                  if (m != null)
                    Text(
                      '${m.name} · ${m.id}\n${m.supplementDate ?? 'No supplement date'}',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
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
class PlayerPanel extends StatefulWidget {
  const PlayerPanel({
    required this.controller,
    required this.onClose,
    this.player,
    this.sectionId,
    this.memberLookup = fetchMember,
    this.identityLookup = fetchMembership,
    this.memberSearch = searchMembers,
    this.focusField,
    super.key,
  });
  final TournamentController controller;
  final String? focusField;

  /// Where a new player goes by default: the section on screen.
  final String? sectionId;

  /// Null to add a new player.
  final Player? player;
  final Future<MemberObservation?> Function(TournamentController, String)
  memberLookup;
  final Future<MemberObservation?> Function(TournamentController, String)
  identityLookup;
  final Future<List<MemberObservation>> Function(String) memberSearch;
  final VoidCallback onClose;
  @override
  State<PlayerPanel> createState() => PlayerPanelState();
}

class PlayerPanelState extends State<PlayerPanel> {
  static const _fields = [
    ('name', 'Full name', 1),
    ('memberId', 'US Chess ID', 1),
    ('rating', 'Rating', 1),
    ('state', 'State (2 letters)', 1),
    ('reportName', 'Name on rating report', 1),
    ('team', 'Team / mixed-doubles name', 1),
    ('notes', 'Private notes', 3),
  ];
  final text = {for (final f in _fields) f.$1: TextEditingController()};
  final fieldFocus = {for (final f in _fields) f.$1: FocusNode()};

  void focusRequestedField() {
    final node = fieldFocus[widget.focusField ?? 'name'];
    if (node == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      node.requestFocus();
      if (node.context != null) {
        Scrollable.ensureVisible(node.context!, alignment: 0.2);
      }
    });
  }

  final reason = TextEditingController();
  late FormDraft draft;
  final joinDraft = TextEditingController();
  final moveTarget = TextEditingController();
  String? error;

  /// A move waiting for a reason, because play has started.
  String? moveTo;
  String? swapWith;
  int? moveRevision;
  String? pendingRating;
  int? lookupRevision;

  /// US Chess lookup: in progress, result, or failure message.
  bool looking = false;
  MemberObservation? member;
  String? lookupError;
  int _lookupGeneration = 0;
  String _lastMemberIdText = '';

  void invalidateLookup() {
    _lookupGeneration++;
    looking = false;
    member = null;
    pendingRating = null;
    lookupError = null;
  }

  void memberIdChanged() {
    final value = text['memberId']!.text;
    if (value == _lastMemberIdText) return;
    _lastMemberIdText = value;
    setState(invalidateLookup);
  }

  void applyMember(MemberObservation observation, void Function(Player) save) {
    if (member != observation || widget.player == null) return;
    final player = fresh;
    if (player.memberId != observation.id ||
        text['memberId']!.text.trim() != observation.id) {
      return;
    }
    attempt(() => save(player));
  }

  /// The last player added, confirmed under the add form.
  String? added;

  /// The section a new player joins; null leaves them unsectioned.
  late String? joinSection = widget.sectionId;

  TournamentController get c => widget.controller;
  Map<String, String> get values => text.map((k, v) => MapEntry(k, v.text));
  bool get dirty => !mapEquals(values, stored(widget.player));

  static Map<String, String> stored(Player? p) => {
    'name': p?.name ?? '',
    'memberId': p?.memberId ?? '',
    'rating': p == null ? '' : ratingText(p.rating),
    'state': p?.state ?? '',
    'reportName': p?.reportName ?? '',
    'team': p?.team ?? '',
    'notes': p?.notes ?? '',
  };

  void load() {
    final v = stored(widget.player);
    for (final e in text.entries) {
      e.value.text = v[e.key]!;
    }
    error = null;
  }

  @override
  void initState() {
    super.initState();
    load();
    restoreDraft();
    _lastMemberIdText = text['memberId']!.text;
    text['memberId']!.addListener(memberIdChanged);
    focusRequestedField();
  }

  void restoreDraft() {
    draft = FormDraft(
      c.workspaceState,
      'draft-player-${widget.player?.id ?? 'new'}',
      {
        ...text,
        'join': joinDraft,
        'moveReason': reason,
        'moveTarget': moveTarget,
      },
      {
        ...stored(widget.player),
        'join': widget.sectionId ?? '',
        'moveReason': '',
        'moveTarget': '',
      },
    );
    moveTo = c.event!.sections.any((s) => s.id == moveTarget.text)
        ? moveTarget.text
        : null;
    joinSection = joinDraft.text.isEmpty ? null : joinDraft.text;
    if (!c.event!.sections.any((s) => s.id == joinSection)) joinSection = null;
  }

  void discardDraft() {
    draft.reset({
      ...stored(widget.player),
      'join': widget.sectionId ?? '',
      'moveReason': '',
      'moveTarget': '',
    });
    joinSection = widget.sectionId;
    moveTo = null;
    setState(() => error = null);
  }

  @override
  void didUpdateWidget(PlayerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.focusField != widget.focusField ||
        old.player?.id != widget.player?.id) {
      focusRequestedField();
    }
    if (old.controller != widget.controller ||
        old.player?.id != widget.player?.id ||
        (old.player?.memberId != widget.player?.memberId &&
            widget.player?.memberId != text['memberId']!.text.trim())) {
      invalidateLookup();
    }
    if (old.player?.id != widget.player?.id) {
      draft.dispose();
      moveTo = null;
      swapWith = null;
      moveRevision = null;
      reason.clear();
      member = null;
      lookupError = null;
      load();
      restoreDraft();
    } else {
      draft.reconcile(stored(widget.player));
    }
  }

  @override
  void dispose() {
    draft.dispose();
    for (final node in fieldFocus.values) {
      node.dispose();
    }
    joinDraft.dispose();
    moveTarget.dispose();
    for (final t in text.values) {
      t.dispose();
    }
    reason.dispose();
    super.dispose();
  }

  Player get fresh => c.event!.player(widget.player!.id);

  /// Runs a change, showing any failure in the panel.
  bool attempt(void Function() change) {
    try {
      change();
      if (error != null) setState(() => error = null);
      return true;
    } catch (e) {
      setState(() => error = plainMessage(e));
      return false;
    }
  }

  /// Saves pending field edits. Returns false and shows why if invalid.
  bool commit() {
    final adding = widget.player == null;
    final current = stored(adding ? null : fresh);
    draft.reconcile(current);
    final conflicts = draft.conflicts(current);
    if (conflicts.isNotEmpty) {
      final names = _fields
          .where((field) => conflicts.contains(field.$1))
          .map((field) => field.$2)
          .join(', ');
      setState(
        () => error =
            '$names changed elsewhere. Discard this draft to load the saved values, then re-enter your changes.',
      );
      return false;
    }
    if (!_fields.any((field) => draft.isEdited(field.$1))) return true;
    final v = values;
    ({String? into, String? problem}) joined = (into: null, problem: null);
    final ok = attempt(() {
      final rating = parseRating(v['rating']!);
      if (v['name']!.trim().isEmpty) {
        throw const TournamentException('Enter the player\'s name.');
      }
      if (rating == null) {
        throw const TournamentException('Enter a rating number, or UNR.');
      }
      final state = v['state']!.trim().toUpperCase();
      if (state.isNotEmpty && !isStateCode(state)) {
        throw const TournamentException(
          'Enter the state as two letters, like MA.',
        );
      }
      final saved = (adding ? Player(id: c.newId(), name: '') : fresh).copy(
        name: v['name']!.trim(),
        memberId: v['memberId']!.trim(),
        rating: rating,
        state: state,
        reportName: v['reportName']!.trim(),
        team: v['team']!.trim(),
        notes: v['notes']!,
      );
      c.savePlayer(saved);
      if (adding) joined = joinNew(saved);
      // Show the saved capitals rather than leaving the panel looking unsaved.
      if (!adding) text['state']!.text = state;
      draft.reset({
        ...stored(adding ? null : saved),
        'join': joinSection ?? '',
        'moveReason': reason.text,
        'moveTarget': moveTarget.text,
      });
    });
    // The add form clears for the next player.
    if (ok && adding) {
      setState(() {
        added = joined.into == null
            ? v['name']!.trim()
            : '${v['name']!.trim()} to ${joined.into}';
        load();
        error = joined.problem;
      });
      fieldFocus['name']!.requestFocus();
    }
    return ok;
  }

  /// Puts a walk-up straight into [joinSection]. Returns where they went,
  /// or, when that cannot happen yet, why; the player stays added either way.
  ({String? into, String? problem}) joinNew(Player p) {
    final s = c.event!.sections.where((s) => s.id == joinSection).firstOrNull;
    if (s == null) return (into: null, problem: null);
    try {
      c.movePlayers([p.id], s.id, reason: s.rounds.isEmpty ? '' : 'Late entry');
      return (into: s.name, problem: null);
    } catch (error) {
      return (
        into: null,
        problem:
            'Added ${p.name}, but not to ${s.name} yet. ${plainMessage(error)}',
      );
    }
  }

  void pickSection(String? target) {
    if (target == null || !commit()) return;
    setState(() {
      moveTo = target;
      moveTarget.text = target;
      moveRevision = c.event!.revision;
      swapWith = null;
    });
  }

  void confirmMove() {
    if (moveRevision != null && moveRevision != c.event!.revision) {
      setState(() {
        error = 'The event changed. Choose the section and review again.';
        moveTo = null;
        swapWith = null;
      });
      return;
    }
    if (attempt(
      () => swapWith != null
          ? c.swapPlayers(
              widget.player!.id,
              swapWith!,
              moveRevision ?? c.event!.revision,
            )
          : c.movePlayers(
              [widget.player!.id],
              moveTo!,
              reason: reason.text.trim(),
            ),
    )) {
      setState(() {
        moveTo = null;
        moveTarget.clear();
        reason.clear();
      });
    }
  }

  Future<void> lookup() async {
    if (!commit()) return;
    final controller = c;
    final playerId = fresh.id, memberId = fresh.memberId;
    final eventId = controller.event!.id;
    final generation = ++_lookupGeneration;
    bool current() =>
        mounted &&
        generation == _lookupGeneration &&
        c == controller &&
        c.event?.id == eventId &&
        widget.player?.id == playerId &&
        text['memberId']!.text.trim() == memberId &&
        c.event!.players.any((p) => p.id == playerId && p.memberId == memberId);
    setState(() {
      looking = true;
      lookupRevision = c.event!.revision;
      pendingRating = null;
      member = null;
      lookupError = null;
    });
    try {
      final found = await widget.memberLookup(controller, memberId);
      if (!current()) return;
      if (found?.id == memberId) {
        final unchanged = lookupRevision == c.event!.revision;
        c.recordMembership(eventId, playerId, found!.toJson());
        if (unchanged) lookupRevision = c.event!.revision;
      }
      setState(() {
        member = found?.id == memberId ? found : null;
        if (found == null) lookupError = 'key';
        if (found != null && found.id != memberId) {
          lookupError = 'The returned member does not match the requested ID.';
        }
      });
    } catch (e) {
      if (current()) setState(() => lookupError = plainMessage(e));
    } finally {
      if (current()) setState(() => looking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fields = [
      for (final (key, label, lines) in _fields) ...[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: TextField(
            key: ValueKey('panel-$key'),
            controller: text[key],
            focusNode: fieldFocus[key],
            autofocus: key == (widget.focusField ?? 'name'),
            maxLines: lines,
            textCapitalization: key == 'state'
                ? TextCapitalization.characters
                : TextCapitalization.none,
            decoration: InputDecoration(
              labelText: label,
              alignLabelWithHint: lines > 1,
              suffixIcon: key == 'memberId' && widget.player != null
                  ? IconButton(
                      tooltip: 'Refresh monthly supplement',
                      onPressed: looking ? null : lookup,
                      icon: const Icon(Icons.refresh, size: 18),
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => commit(),
          ),
        ),
        if (key == 'memberId')
          MemberIdentityLookup(
            key: ValueKey('player-identity-${widget.player?.id ?? 'new'}'),
            id: text['memberId']!,
            name: text['name'],
            lookup: (id) => widget.identityLookup(c, id),
            search: widget.memberSearch,
            onSelected: (member) => setState(() {
              text['memberId']!.text = member.id;
            }),
          ),
      ],
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(error!, style: TextStyle(color: colors.error)),
        ),
    ];
    void close() => widget.onClose();

    final player = widget.player;
    if (player == null) {
      return SidePanel(
        title: 'Add player',
        onClose: close,
        children: [
          DraftStatus(draft: draft),
          ...fields,
          if (c.event!.sections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String?>(
                key: const ValueKey('panel-join-section'),
                initialValue: joinSection,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Section'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Not in a section yet'),
                  ),
                  for (final s in c.event!.sections)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() {
                  joinSection = v;
                  joinDraft.text = v ?? '';
                }),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                FilledButton(onPressed: commit, child: const Text('Add')),
                TextButton(
                  onPressed: discardDraft,
                  child: const Text('Discard draft'),
                ),
              ],
            ),
          ),
          if (added != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Added $added. Enter the next player, or close.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
        ],
      );
    }
    final e = c.event!, p = player, s = e.sectionOf(p.id);
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
    final membership = MembershipSummary(p, eventDate: e.lastDate);
    final checkedAt = p.membershipEvidence['id'] == p.memberId
        ? DateTime.tryParse('${p.membershipEvidence['retrievedAt']}')
        : null;
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
    // Byes can be requested for rounds not yet paired.
    final planned =
        s?.plannedRounds ??
        e.sections.fold<int>(
          0,
          (n, x) => x.plannedRounds > n ? x.plannedRounds : n,
        );
    final open = [
      for (var r = (s?.rounds.length ?? 0) + 1; r <= planned; r++) r,
    ];
    return SidePanel(
      title: p.name,
      onClose: close,
      children: [
        DraftStatus(draft: draft),
        if (p.withdrawn)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Withdrawn', style: muted),
          ),
        ...fields,
        if (dirty)
          Wrap(
            spacing: 8,
            children: [
              FilledButton(onPressed: commit, child: const Text('Save')),
              const SizedBox(width: 8),
              TextButton(
                onPressed: discardDraft,
                child: const Text('Discard draft'),
              ),
            ],
          ),
        if (p.ratingEvidence.isNotEmpty)
          Text(
            p.ratingEvidence['supplementDate'] != null
                ? 'Monthly supplement: ${p.ratingEvidence['supplementDate']}'
                : 'Registration rating: ${p.ratingEvidence['registrationRating'] ?? p.rating}',
          ),
        heading('US Chess'),
        Text(
          checkedAt != null && p.memberId.isNotEmpty
              ? 'Expires: ${membership.label}'
              : membership.label,
          style: TextStyle(color: membershipColor(colors, membership)),
        ),
        if (checkedAt != null && p.memberId.isNotEmpty)
          Text(
            'Checked: ${checkedAt.toIso8601String().substring(0, 10)}',
            style: muted,
          ),
        if (p.memberId.isEmpty)
          Text('Enter a US Chess ID to look the player up.', style: muted)
        else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: looking ? null : lookup,
              child: Text(looking ? 'Looking up…' : 'Look up ${p.memberId}'),
            ),
          ),
          if (lookupError == 'key')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Looking up IDs needs a US Chess API key.',
                    style: muted,
                  ),
                  const SizedBox(height: 8),
                  ApiKeyField(onSaved: lookup),
                ],
              ),
            )
          else if (lookupError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(lookupError!, style: TextStyle(color: colors.error)),
            ),
          if (member case final m?) ...[
            const SizedBox(height: 12),
            Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              'Monthly supplement: ${m.supplementDate ?? 'date unavailable'}',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (m.state case final st?
                    when isStateCode(st) && st != p.state)
                  ActionChip(
                    chipAnimationStyle: noChipAnimation,
                    label: Text('Use state $st'),
                    onPressed: () => applyMember(
                      m,
                      (player) => c.savePlayer(player.copy(state: st)),
                    ),
                  ),
                if (m.reportName case final rn? when rn != playerReportName(p))
                  ActionChip(
                    chipAnimationStyle: noChipAnimation,
                    label: Text('Report as $rn'),
                    tooltip: 'Use the US Chess spelling on the rating report',
                    onPressed: () => applyMember(
                      m,
                      (player) => c.savePlayer(player.copy(reportName: rn)),
                    ),
                  ),
                if (m.name.isNotEmpty && m.name != p.name)
                  ActionChip(
                    chipAnimationStyle: noChipAnimation,
                    label: Text('Use name ${m.name}'),
                    onPressed: () => applyMember(
                      m,
                      (player) => c.savePlayer(player.copy(name: m.name)),
                    ),
                  ),
                for (final r in m.ratings.entries)
                  if (r.value != null)
                    ActionChip(
                      chipAnimationStyle: noChipAnimation,
                      avatar: m.alreadyApplied(p, r.key)
                          ? const Icon(Icons.check, size: 16)
                          : null,
                      label: Text('${r.key} ${r.value}'),
                      tooltip: 'Review this rating for pairings',
                      onPressed:
                          m.alreadyApplied(p, r.key) ||
                              (s?.rounds.isNotEmpty ?? false)
                          ? null
                          : () => setState(() => pendingRating = r.key),
                    ),
              ],
            ),
            if (s?.rounds.isNotEmpty ?? false)
              const Text('Pairings are posted. The pairing rating is kept.'),
            if (pendingRating case final category?) ...[
              const SizedBox(height: 12),
              Text(
                'Confirm ${m.name} (${m.id}): ${p.rating} → ${m.ratings[category]} ($category).',
              ),
              FilledButton(
                onPressed: () {
                  if (lookupRevision != c.event!.revision) {
                    setState(
                      () => lookupError =
                          'The event changed. Refresh and review again.',
                    );
                    return;
                  }
                  applyMember(
                    m,
                    (player) => c.savePlayer(
                      player.copy(
                        rating: m.ratings[category],
                        ratingEvidence: {
                          ...player.ratingEvidence,
                          ...m.toJson(),
                          'kind': 'monthly supplement',
                          'category': category,
                        },
                      ),
                    ),
                  );
                  setState(() => pendingRating = null);
                },
                child: const Text('Confirm rating change'),
              ),
            ],
          ],
        ],
        if (open.isNotEmpty) ...[
          heading('Byes'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Points a requested bye scores in each round not yet paired.',
              style: muted,
            ),
          ),
          for (final r in open)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(width: 72, child: Text('Round $r')),
                  Expanded(
                    child: SegmentedButton<int>(
                      key: ValueKey('panel-bye-$r'),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        padding: WidgetStatePropertyAll(EdgeInsets.zero),
                      ),
                      segments: const [
                        ButtonSegment(value: -1, label: Text('None')),
                        ButtonSegment(value: 1, label: Text('1/2')),
                        ButtonSegment(value: 0, label: Text('0')),
                        ButtonSegment(value: 2, label: Text('1')),
                      ],
                      selected: {p.byes[r] ?? -1},
                      onSelectionChanged: p.withdrawn
                          ? null
                          : (v) =>
                                attempt(() => c.reserveBye(p.id, r, v.single)),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (e.sections.isNotEmpty) ...[
          heading('Section'),
          DropdownButton<String>(
            key: const ValueKey('panel-section'),
            value: moveTo ?? s?.id,
            hint: const Text('Not in a section'),
            isExpanded: true,
            items: [
              for (final x in e.sections)
                DropdownMenuItem(value: x.id, child: Text(x.name)),
            ],
            onChanged: pickSection,
          ),
          if (moveTo != null) ...[
            const SizedBox(height: 8),
            Text(
              'Move ${p.name} from ${s?.name ?? 'Unassigned'} to ${e.sections.firstWhere((x) => x.id == moveTo).name}. Confirm below. A reason is required after play.',
              style: muted,
            ),
            if (s != null &&
                s.rounds.isEmpty &&
                e.sections
                    .firstWhere((x) => x.id == moveTo)
                    .rounds
                    .isEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: swapWith ?? '',
                key: ValueKey('swap-partner-$moveTo'),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Move or exchange places',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Move without a swap'),
                  ),
                  for (final id
                      in e.sections.firstWhere((x) => x.id == moveTo).players)
                    if (id != p.id)
                      DropdownMenuItem(
                        value: id,
                        child: Text('Swap with ${e.player(id).name}'),
                      ),
                ],
                onChanged: (value) =>
                    setState(() => swapWith = value == '' ? null : value),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason'),
              onSubmitted: (_) => confirmMove(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: confirmMove,
                  child: Text(
                    swapWith == null ? 'Confirm move' : 'Confirm swap',
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() {
                    moveTo = null;
                    moveTarget.clear();
                    reason.clear();
                  }),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ],
        heading('Pairing requests'),
        if (e.sections.any(
          (x) =>
              x.rounds.isEmpty &&
              !x.players.any(
                (id) => (e.player(id).personId ?? id) == (p.personId ?? p.id),
              ),
        )) ...[
          PopupMenuButton<String>(
            key: const ValueKey('add-separate-section-entry'),
            tooltip: 'Add a separate section entry',
            onSelected: (id) => attempt(() {
              c.addSectionEntry(p.id, id);
            }),
            itemBuilder: (_) => [
              for (final x in e.sections.where(
                (x) =>
                    x.rounds.isEmpty &&
                    !x.players.any(
                      (id) =>
                          (e.player(id).personId ?? id) == (p.personId ?? p.id),
                    ),
              ))
                PopupMenuItem(value: x.id, child: Text(x.name)),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Add a separate section entry…'),
            ),
          ),
          Text(
            'For a side game or another ladder section. Starts a separate score and keeps the original entry.',
            style: muted,
          ),
          const SizedBox(height: 12),
        ],
        Text(
          'Do not pair with these players in future rounds. For siblings or other requests; independent of team membership.',
          style: muted,
        ),
        const SizedBox(height: 8),
        for (final other in e.players.where(
          (other) =>
              other.id != p.id &&
              (p.avoid.contains(other.id) || other.avoid.contains(p.id)),
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InputChip(
              label: Text(other.name),
              onDeleted: () =>
                  attempt(() => c.avoidPair(p.id, other.id, false)),
              deleteButtonTooltipMessage: 'Allow pairing with ${other.name}',
            ),
          ),
        // Typed, not scrolled: a club event has 100+ names.
        Autocomplete<Player>(
          key: ValueKey('avoid-${p.id}-${p.avoid.length}'),
          displayStringForOption: (o) => o.name,
          optionsBuilder: (value) {
            final q = value.text.trim().toLowerCase();
            if (q.isEmpty) return const [];
            return e.players.where(
              (o) =>
                  o.id != p.id &&
                  !p.avoid.contains(o.id) &&
                  o.name.toLowerCase().contains(q),
            );
          },
          onSelected: (o) => attempt(() => c.avoidPair(p.id, o.id, true)),
          fieldViewBuilder: (context, text, focus, submit) => TextField(
            key: const ValueKey('avoid-player'),
            controller: text,
            focusNode: focus,
            decoration: const InputDecoration(
              labelText: 'Avoid pairing with',
              prefixIcon: Icon(Icons.person_off_outlined, size: 18),
            ),
            onSubmitted: (_) => submit(),
          ),
        ),
        if (s != null && s.format != Format.swiss)
          Text(
            'In a quad or round robin everyone must meet. Put these players in different sections to honor the request.',
            style: muted,
          ),
        heading('Status'),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => attempt(
              () => c.savePlayer(fresh.copy(withdrawn: !p.withdrawn)),
            ),
            child: Text(p.withdrawn ? 'Reinstate' : 'Withdraw'),
          ),
        ),
      ],
    );
  }
}

enum _Side { fileImport, player, add, paste, team, membership }

/// Every tool shares the same reserved column, even while it is closed.
double detailsColumnWidth(double availableWidth) =>
    (availableWidth * 0.48).clamp(0.0, 360.0);

/// Keeps a stable details column so opening a panel never reflows the table.
class PlayerDetailsLayout extends StatelessWidget {
  const PlayerDetailsLayout({
    required this.child,
    this.panel,
    this.expandContent = false,
    this.reserveSpace = true,
    super.key,
  });
  final Widget child;
  final Widget? panel;
  final bool expandContent;
  final bool reserveSpace;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final panelWidth = panel == null && !reserveSpace
          ? 0.0
          : detailsColumnWidth(constraints.maxWidth);
      final contentWidth = (constraints.maxWidth - panelWidth).clamp(
        0.0,
        expandContent ? double.infinity : 1100.0,
      );
      // Small windows can scroll across the table and details together.
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth < contentWidth + panelWidth
              ? contentWidth + panelWidth
              : constraints.maxWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: contentWidth, child: child),
              const Spacer(),
              SizedBox(
                key: const ValueKey('player-details-area'),
                width: panelWidth,
                child: panel == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: panel,
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A panel docked beside a table. Esc or the close button calls [onClose].
class SidePanel extends StatelessWidget {
  const SidePanel({
    required this.title,
    required this.onClose,
    required this.children,
    this.footer = const [],
    this.width = 360,
    this.scrolls = true,
    super.key,
  });
  final String title;
  final VoidCallback onClose;
  final List<Widget> children;
  final List<Widget> footer;
  final double width;

  /// False when the single child fills the panel and scrolls itself.
  final bool scrolls;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // A fresh scope lets field autofocus take over from the workspace.
    return FocusScope(
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
        child: Container(
          width: width,
          margin: const EdgeInsets.fromLTRB(0, 0, 24, 16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            border: Border.all(color: colors.outlineVariant),
          ),
          // List tiles inside draw their highlight on this.
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close (Esc)',
                        icon: const Icon(Icons.close),
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: scrolls
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: children,
                          ),
                        )
                      : children.single,
                ),
                if (footer.isNotEmpty) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: footer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastes spreadsheet rows as players. The text is kept as a draft until
/// it imports.
class _PastePanel extends StatefulWidget {
  const _PastePanel({
    required this.controller,
    required this.onClose,
    required this.onImported,
  });
  final TournamentController controller;
  final VoidCallback onClose;
  final ValueChanged<String> onImported;
  @override
  State<_PastePanel> createState() => _PastePanelState();
}

class _PastePanelState extends State<_PastePanel> {
  late final text = TextEditingController(
    text: widget.controller.workspaceState.read('import-draft') ?? '',
  );
  bool reviewing = false;

  void review() {
    if (text.text.trim().isNotEmpty) setState(() => reviewing = true);
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reviewing) {
      return RosterImportPanel(
        controller: widget.controller,
        source: text.text,
        filename: 'Pasted spreadsheet',
        onClose: () => setState(() => reviewing = false),
        onImported: (summary) {
          widget.controller.workspaceState.write('import-draft', '');
          text.clear();
          widget.onImported(summary);
        },
      );
    }
    final colors = Theme.of(context).colorScheme;
    final draftError =
        widget.controller.workspaceState.failures['import-draft'];
    return SidePanel(
      title: 'Paste players',
      onClose: widget.onClose,
      children: [
        Text(
          'Paste your rows, then review the columns before importing.',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 12),
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): review,
            const SingleActivator(LogicalKeyboardKey.numpadEnter): review,
          },
          child: TextField(
            key: const ValueKey('paste-roster'),
            controller: text,
            autofocus: true,
            minLines: 10,
            maxLines: 20,
            decoration: const InputDecoration(
              helperText: 'Enter to review · Shift+Enter for a new line',
              helperMaxLines: 2,
            ),
            onChanged: (v) {
              widget.controller.workspaceState.write('import-draft', v);
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 12),
        if (draftError != null || text.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              draftError == null
                  ? 'Draft saved · not imported'
                  : 'Draft not saved to disk. $draftError',
              style: TextStyle(
                color: draftError == null
                    ? colors.onSurfaceVariant
                    : colors.error,
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: text.text.trim().isEmpty ? null : review,
                child: const Text('Review import'),
              ),
              if (widget.controller.workspaceState.failures.containsKey(
                'import-draft',
              ))
                TextButton(
                  onPressed: () {
                    widget.controller.workspaceState.retry();
                    setState(() {});
                  },
                  child: const Text('Retry draft save'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Keep the date visible; warnings and provenance are also readable by assistive technology.
class _MembershipCell extends StatelessWidget {
  const _MembershipCell({required this.player, required this.eventDate});
  final Player player;
  final String eventDate;

  @override
  Widget build(BuildContext context) {
    final summary = MembershipSummary(player, eventDate: eventDate);
    final colors = Theme.of(context).colorScheme;
    final color = membershipColor(colors, summary);
    return Tooltip(
      message: summary.detail,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    summary.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (summary.attention) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.warning_amber_rounded, size: 14, color: color),
                ],
              ],
            ),
            if (summary.warning != null)
              Text(
                summary.warning!,
                style: TextStyle(color: color, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
