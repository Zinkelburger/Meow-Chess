import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/tournament_controller.dart';
import '../domain/model.dart';
import '../domain/pairing.dart';
import '../domain/standings.dart';
import '../domain/us_chess.dart';
import '../infrastructure/roster_import.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'identity_review.dart';
import 'results_view.dart' show scoreMark;
import '../infrastructure/ratings_api.dart';

/// Picks a CSV/TSV/TXT roster file and imports it.
Future<void> importRosterFile(
  BuildContext context,
  TournamentController c,
) async {
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
    if (file == null) return;
    final summary = importRoster(c, await file.readAsString());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(summary),
        duration: const Duration(seconds: 8),
        showCloseIcon: true,
        action: SnackBarAction(label: 'Undo', onPressed: c.undo),
      ),
    );
  } catch (e) {
    if (context.mounted) showFailure(context, e);
  }
}

/// Imports roster text and returns a one-line summary.
String importRoster(TournamentController c, String source) {
  final rows = parseRoster(source);
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

/// ¼-point units (Sonneborn–Berger) as a short label: 0, ¼, 2½, 3¾ …
String quarters(int n) {
  final whole = n ~/ 4, part = const ['', '¼', '½', '¾'][n % 4];
  return whole == 0 && part.isNotEmpty ? part : '$whole$part';
}

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
    this.onAddSections,
    super.key,
  });
  final TournamentController controller;
  final String? sectionId;
  final VoidCallback? onAddSections;
  @override
  State<PlayersView> createState() => _PlayersViewState();
}

class _PlayersViewState extends State<PlayersView> {
  final search = TextEditingController();
  final selected = <String>{};
  final panel = GlobalKey<PlayerPanelState>();

  /// What the side panel shows: a player, a new player, or pasting.
  _Side? side;

  /// The player shown when [side] is [_Side.player].
  String? open;

  /// A move of the ticked players waiting for a reason.
  String? moveTo;
  final moveReason = TextEditingController();

  /// Rank players by score instead of seed. Null follows the event: by
  /// score once a round is paired.
  bool? byScore;

  /// Standings options: count only prize-eligible players, and show only
  /// players rated under this (0 for everyone).
  bool prizes = false;
  int ceiling = 0;

  /// Players in on-screen order, for arrow-key movement.
  List<Player> order = const [];
  int rounds = 0;

  /// Whether the table shows points and tiebreaks.
  bool scores = false;
  bool showTiebreaks = false;
  bool showIds = false;
  TournamentController get c => widget.controller;

  // Fixed column widths keep the table narrow and aligned.
  static const _check = 40.0,
      _number = 36.0,
      _name = 240.0,
      _rating = 64.0,
      _id = 100.0,
      _round = 76.0,
      _points = 52.0,
      _tiebreak = 52.0;

  @override
  void dispose() {
    search.dispose();
    moveReason.dispose();
    super.dispose();
  }

  /// Changes the side panel, saving the previous player's edits first.
  void showSide(_Side? next, [String? id]) {
    if (next == side && id == open) return;
    if (panel.currentState?.commit() == false) return;
    setState(() {
      side = next;
      open = id;
    });
  }

  void openPlayer(String id) => showSide(_Side.player, id);

  /// Moves the ticked players. Once play has started a reason is asked for
  /// in the selection bar first.
  void moveSelected(String targetId, {String reason = ''}) {
    final started = c.event!.sections.any(
      (s) =>
          (s.id == targetId || s.players.any(selected.contains)) &&
          s.rounds.isNotEmpty,
    );
    if (started && reason.isEmpty) {
      setState(() => moveTo = targetId);
      return;
    }
    try {
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
    if (reason.isEmpty) {
      showFailure(context, 'Give a reason for the move.');
      return;
    }
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

  bool matches(Player p) {
    final q = search.text.trim().toLowerCase();
    return q.isEmpty ||
        p.name.toLowerCase().contains(q) ||
        p.memberId.contains(q) ||
        p.team.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final e = c.event!, colors = Theme.of(context).colorScheme;
    if (side == _Side.player && !e.players.any((p) => p.id == open)) {
      side = open = null;
    }
    final panelWidget = switch (side) {
      _Side.player => PlayerPanel(
        key: panel,
        controller: c,
        player: e.player(open!),
        onClose: () => showSide(null),
      ),
      _Side.add => PlayerPanel(
        key: panel,
        controller: c,
        onClose: () => showSide(null),
      ),
      _Side.paste => _PastePanel(controller: c, onClose: () => showSide(null)),
      null => null,
    };
    if (e.players.isEmpty) {
      return PlayerDetailsLayout(panel: panelWidget, child: _welcome(context));
    }
    selected.removeWhere((id) => !e.players.any((p) => p.id == id));
    // Sections list players in seed order, or by standings once play has
    // started; loose players sort by rating.
    final started = e.sections.any(
      (s) =>
          s.rounds.isNotEmpty &&
          (widget.sectionId == null || s.id == widget.sectionId),
    );
    final ranked = started && (byScore ?? true);
    final tables = <String, Map<String, Standing>>{
      for (final s in e.sections)
        if (s.rounds.isNotEmpty)
          s.id: {
            for (final row in standings(e, s, forPrizes: ranked && prizes))
              row.player.id: row,
          },
    };
    bool inClass(Player p) =>
        !ranked || ceiling == 0 || (p.rating > 0 && p.rating < ceiling);
    List<Player> ordered(Section s) {
      final table = tables[s.id];
      if (!ranked || table == null) {
        return s.players.map(e.player).where(matches).toList();
      }
      return [
        for (final row in table.values) row.player,
        for (final id in s.players)
          if (!table.containsKey(id)) e.player(id),
      ].where((p) => matches(p) && inClass(p)).toList();
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
    final unassigned = e.players.where((p) => e.sectionOf(p.id) == null).length;
    final shown = groups.fold(0, (int n, g) => n + g.$2.length);
    rounds = groups
        .map((g) => g.$1?.plannedRounds ?? 0)
        .fold(0, (int a, b) => a > b ? a : b);
    order = [for (final g in groups) ...g.$2];
    final items = <Widget>[
      for (final (s, players) in groups) ...[
        _groupHeader(context, s, players),
        if (players.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Text(
              'No players. Tick players below and move them here.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
        for (final p in players)
          _row(
            context,
            '${e.players.indexWhere((x) => x.id == p.id) + 1}',
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
        _check +
        _number +
        _name +
        _rating +
        (showIds ? _id : 0) +
        rounds * _round +
        (started ? _points + (showTiebreaks ? 2 * _tiebreak : 0) : 0) +
        28;
    return PlayerDetailsLayout(
      panel: panelWidget,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Players',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  started
                      ? '$shown players · W win, D draw, L loss + opponent # · B bye · Edit results in Rounds.'
                      : '$shown players · Select a name to edit details or request a bye.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final searchBox = SizedBox(
                      width: constraints.maxWidth < 300
                          ? constraints.maxWidth
                          : 280,
                      child: TextField(
                        key: const ValueKey('player-search'),
                        controller: search,
                        decoration: InputDecoration(
                          hintText: 'Search players',
                          prefixIcon: const Icon(Icons.search, size: 20),
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
                    );
                    final actions = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (started)
                          SegmentedButton<bool>(
                            key: const ValueKey('player-order'),
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: true,
                                label: Text('Standings'),
                              ),
                              ButtonSegment(
                                value: false,
                                label: Text('Seed order'),
                              ),
                            ],
                            selected: {ranked},
                            onSelectionChanged: (v) =>
                                setState(() => byScore = v.first),
                          ),
                        MenuAnchor(
                          builder: (context, menu, child) => TextButton.icon(
                            onPressed: () =>
                                menu.isOpen ? menu.close() : menu.open(),
                            icon: const Icon(Icons.tune, size: 18),
                            label: const Text('View'),
                          ),
                          menuChildren: [
                            CheckboxMenuButton(
                              value: showIds,
                              onChanged: (v) => setState(() => showIds = v!),
                              child: const Text('US Chess IDs'),
                            ),
                            CheckboxMenuButton(
                              value: showTiebreaks,
                              onChanged: (v) =>
                                  setState(() => showTiebreaks = v!),
                              child: const Text('Tiebreaks (BH / SB)'),
                            ),
                            if (ranked) ...[
                              const Divider(),
                              SubmenuButton(
                                menuChildren: [
                                  for (final n in [
                                    0,
                                    2200,
                                    2000,
                                    1900,
                                    1800,
                                    1600,
                                    1500,
                                    1400,
                                    1200,
                                  ])
                                    RadioMenuButton<int>(
                                      value: n,
                                      groupValue: ceiling,
                                      onChanged: (v) =>
                                          setState(() => ceiling = v!),
                                      child: Text(
                                        n == 0 ? 'All ratings' : 'Under $n',
                                      ),
                                    ),
                                ],
                                child: const Text('Rating filter'),
                              ),
                              CheckboxMenuButton(
                                value: prizes,
                                onChanged: (v) => setState(() => prizes = v!),
                                child: const Text(
                                  'Exclude early round-robin withdrawals',
                                ),
                              ),
                            ],
                          ],
                        ),
                        OutlinedButton.icon(
                          onPressed: () => showSide(_Side.add),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add player'),
                        ),
                        MenuAnchor(
                          builder: (context, menu, child) => IconButton(
                            tooltip: 'Import players',
                            icon: const Icon(Icons.more_horiz),
                            onPressed: () =>
                                menu.isOpen ? menu.close() : menu.open(),
                          ),
                          menuChildren: [
                            MenuItemButton(
                              leadingIcon: const Icon(
                                Icons.upload_file_outlined,
                              ),
                              onPressed: () => importRosterFile(context, c),
                              child: const Text('Import file…'),
                            ),
                            MenuItemButton(
                              leadingIcon: const Icon(Icons.content_paste),
                              onPressed: () => showSide(_Side.paste),
                              child: const Text('Paste from spreadsheet'),
                            ),
                          ],
                        ),
                      ],
                    );
                    if (constraints.maxWidth /
                            MediaQuery.textScalerOf(context).scale(1) <
                        1000) {
                      return Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        children: [searchBox, actions],
                      );
                    }
                    return Row(children: [searchBox, const Spacer(), actions]);
                  },
                ),
                if (ranked && (ceiling != 0 || prizes))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (ceiling != 0)
                          InputChip(
                            label: Text('Under $ceiling'),
                            onDeleted: () => setState(() => ceiling = 0),
                          ),
                        if (prizes)
                          InputChip(
                            label: const Text('Early withdrawals excluded'),
                            onDeleted: () => setState(() => prizes = false),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (unassigned > 0 && widget.onAddSections != null)
            _banner(
              context,
              '$unassigned ${unassigned == 1 ? 'player is' : 'players are'} not in a section yet.',
              FilledButton(
                onPressed: widget.onAddSections,
                child: const Text('Create sections…'),
              ),
            ),
          _selectionBar(context),
          Expanded(child: _table(context, items, width)),
        ],
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
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final minimum =
                    width * MediaQuery.textScalerOf(context).scale(14) / 14;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: constraints.maxWidth > minimum
                        ? constraints.maxWidth
                        : minimum,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLowest,
                        border: Border.all(color: colors.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _columns(context, rounds),
                          Expanded(child: ListView(children: items)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
  }

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
            const Text(
              'Import a CSV or tab-separated file with columns Name, US Chess ID and Rating. A header row is optional.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => importRosterFile(context, c),
                  child: const Text('Import players from file…'),
                ),
                OutlinedButton(
                  onPressed: () => showSide(_Side.paste),
                  child: const Text('Paste from spreadsheet'),
                ),
                OutlinedButton(
                  onPressed: () => showSide(_Side.add),
                  child: const Text('Add one player'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _banner(BuildContext context, String text, Widget action) => Container(
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
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
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      height: controlHeight + 12,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: selected.isNotEmpty && moveTo != null
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  Text(
                    'Move ${selected.length == 1 ? e.player(selected.single).name : '${selected.length} players'} to ${e.sections.firstWhere((s) => s.id == moveTo).name}. Rounds have been played; reason:',
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      key: const ValueKey('move-reason'),
                      controller: moveReason,
                      autofocus: true,
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
                    onPressed: () async {
                      final ids = selected.toList();
                      final teams = ids.map((id) => e.player(id).team).toSet();
                      await editFields(
                        context,
                        title: 'Team for ${ids.length} players',
                        description:
                            'Use the same name for mixed-doubles partners. Leave blank to remove the team. Team membership does not change individual pairings.',
                        fields: const [FieldSpec('team', 'Team name')],
                        values: {'team': teams.length == 1 ? teams.single : ''},
                        onSave: (v) => c.assignTeam(ids, v['team'] ?? ''),
                      );
                    },
                    icon: const Icon(Icons.group_outlined, size: 18),
                    label: const Text('Assign team'),
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
                    onPressed: () => setState(selected.clear),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _columns(BuildContext context, int rounds) {
    final colors = Theme.of(context).colorScheme;
    Widget cell(double width, String text, {bool center = false}) => SizedBox(
      width: width,
      child: Text(text, textAlign: center ? TextAlign.center : null),
    );
    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: colors.onSurfaceVariant,
        ),
        child: Row(
          children: [
            const SizedBox(width: _check),
            cell(_number, '#'),
            const Expanded(child: Text('NAME')),
            cell(_rating, 'RATING'),
            if (showIds) cell(_id, 'US CHESS ID'),
            for (var r = 1; r <= rounds; r++) cell(_round, 'R$r', center: true),
            if (scores) ...[
              cell(_points, 'PTS', center: true),
              if (showTiebreaks)
                Tooltip(
                  message:
                      'Buchholz: the total score of everyone this player has played',
                  child: cell(_tiebreak, 'BH', center: true),
                ),
              if (showTiebreaks)
                Tooltip(
                  message:
                      'Sonneborn–Berger: opponents\' scores, weighted by this player\'s result against each',
                  child: cell(_tiebreak, 'SB', center: true),
                ),
            ],
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
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.outlineVariant),
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _check,
            child: Align(
              alignment: Alignment.centerLeft,
              child: PlainCheckbox(
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
                  TextSpan(
                    text:
                        '   ${['${s?.players.length ?? players.length} players', if (s != null) pairingFormat(s) == s.format ? formatName(s.format) : 'Quad · will pair as a small Swiss', if (s != null) boardRange(s), if (s != null && s.rounds.isNotEmpty) 'round ${s.rounds.length} of ${s.plannedRounds}'].join(' · ')}',
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

  /// Read-only result with the stable roster number of the opponent.
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
    String mark(Game g) {
      if (!g.outcome.resolved) return g.outcome == Outcome.disputed ? '?' : '—';
      final white = g.white == pid;
      final score = white ? g.outcome.whiteScore : g.outcome.blackScore;
      final opponent = white ? g.black : g.white;
      final number = e.players.indexWhere((p) => p.id == opponent) + 1;
      final result = score == 2
          ? 'W'
          : score == 1
          ? 'D'
          : 'L';
      return '$result$number${g.outcome.played ? '' : 'F'}';
    }

    return (games.map(mark).join('/'), tip);
  }

  Widget _roundCell(BuildContext context, Player p, Section? s, int r) {
    final colors = Theme.of(context).colorScheme;
    if (s != null && r > s.plannedRounds) return const SizedBox(width: _round);
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
    return SizedBox(
      width: _round,
      child: Tooltip(
        message: tip,
        child: Semantics(
          label: tip,
          child: Padding(
            key: ValueKey('round-${p.id}-$r'),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Text(
              mark,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ),
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
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
    return InkWell(
      key: ValueKey('player-${p.id}'),
      onTap: () => openPlayer(p.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: open == p.id ? colors.primary.withValues(alpha: 0.1) : null,
          border: Border(
            bottom: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _check,
              child: Align(
                alignment: Alignment.centerLeft,
                child: PlainCheckbox(
                  value: selected.contains(p.id),
                  onChanged: (v) => setState(
                    () => v! ? selected.add(p.id) : selected.remove(p.id),
                  ),
                ),
              ),
            ),
            cell(_number, number, muted),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: p.name,
                      style: TextStyle(
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
            cell(
              _rating,
              ratingText(p.rating),
              const TextStyle(fontFamily: 'SourceCodePro'),
            ),
            if (showIds)
              cell(
                _id,
                p.memberId.isEmpty ? '—' : p.memberId,
                muted.copyWith(fontFamily: 'SourceCodePro'),
              ),
            for (var r = 1; r <= rounds; r++) _roundCell(context, p, s, r),
            if (scores) ...[
              SizedBox(
                width: _points,
                child: Text(
                  standing == null ? '' : halves(standing.points),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (showTiebreaks)
                for (final value in [
                  standing == null ? '' : halves(standing.buchholz),
                  standing == null ? '' : quarters(standing.sonneborn),
                ])
                  SizedBox(
                    width: _tiebreak,
                    child: Text(
                      value,
                      textAlign: TextAlign.center,
                      style: muted.copyWith(fontSize: 13),
                    ),
                  ),
            ],
          ],
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
    this.memberLookup = fetchMember,
    super.key,
  });
  final TournamentController controller;

  /// Null to add a new player.
  final Player? player;
  final Future<MemberObservation?> Function(TournamentController, String)
  memberLookup;
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
  final reason = TextEditingController();
  String? error;

  /// A move waiting for a reason, because play has started.
  String? moveTo;

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
    _lastMemberIdText = text['memberId']!.text;
    text['memberId']!.addListener(memberIdChanged);
  }

  @override
  void didUpdateWidget(PlayerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.controller != widget.controller ||
        old.player?.id != widget.player?.id ||
        (old.player?.memberId != widget.player?.memberId &&
            widget.player?.memberId != text['memberId']!.text.trim())) {
      invalidateLookup();
    }
    if (old.player?.id != widget.player?.id) {
      moveTo = null;
      reason.clear();
      member = null;
      lookupError = null;
      load();
    } else if (mapEquals(values, stored(old.player))) {
      // Follow outside changes (undo, lookup) unless the user is mid-edit.
      load();
    }
  }

  @override
  void dispose() {
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
      setState(() => error = '$e');
      return false;
    }
  }

  /// Saves pending field edits. Returns false and shows why if invalid.
  bool commit() {
    if (!dirty) return true;
    final v = values, adding = widget.player == null;
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
      c.savePlayer(
        (adding ? Player(id: c.newId(), name: '') : fresh).copy(
          name: v['name']!.trim(),
          memberId: v['memberId']!.trim(),
          rating: rating,
          state: state,
          reportName: v['reportName']!.trim(),
          team: v['team']!.trim(),
          notes: v['notes']!,
        ),
      );
      // Show the saved capitals rather than leaving the panel looking unsaved.
      if (!adding) text['state']!.text = state;
    });
    // The add form clears for the next player.
    if (ok && adding) {
      setState(() {
        added = v['name']!.trim();
        load();
      });
    }
    return ok;
  }

  void pickSection(String? target) {
    if (target == null || !commit()) return;
    final e = c.event!;
    final started = e.sections.any(
      (s) =>
          (s.id == target || s.players.contains(widget.player!.id)) &&
          s.rounds.isNotEmpty,
    );
    if (started) {
      setState(() => moveTo = target);
    } else {
      attempt(() => c.movePlayers([widget.player!.id], target));
    }
  }

  void confirmMove() {
    if (reason.text.trim().isEmpty) {
      setState(() => error = 'Give a reason for the move.');
      return;
    }
    if (attempt(
      () => c.movePlayers(
        [widget.player!.id],
        moveTo!,
        reason: reason.text.trim(),
      ),
    )) {
      setState(() {
        moveTo = null;
        reason.clear();
      });
    }
  }

  Future<void> lookup() async {
    if (!commit()) return;
    final controller = c;
    final playerId = fresh.id, memberId = fresh.memberId;
    final generation = ++_lookupGeneration;
    bool current() =>
        mounted &&
        generation == _lookupGeneration &&
        c == controller &&
        widget.player?.id == playerId &&
        text['memberId']!.text.trim() == memberId &&
        c.event!.players.any((p) => p.id == playerId && p.memberId == memberId);
    setState(() {
      looking = true;
      member = null;
      lookupError = null;
    });
    try {
      final found = await widget.memberLookup(controller, memberId);
      if (!current()) return;
      setState(() {
        member = found?.id == memberId ? found : null;
        if (found == null) lookupError = 'key';
        if (found != null && found.id != memberId) {
          lookupError = 'The returned member does not match the requested ID.';
        }
      });
    } catch (e) {
      if (current()) setState(() => lookupError = '$e');
    } finally {
      if (current()) setState(() => looking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fields = [
      for (final (i, (key, label, lines)) in _fields.indexed)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: TextField(
            key: ValueKey('panel-$key'),
            controller: text[key],
            autofocus: widget.player == null && i == 0,
            maxLines: lines,
            textCapitalization: key == 'state'
                ? TextCapitalization.characters
                : TextCapitalization.none,
            decoration: InputDecoration(
              labelText: label,
              hintText: switch (key) {
                'rating' => 'UNR',
                // What the report sends when this is left empty.
                'reportName' => reportName(text['name']!.text) ?? '',
                _ => null,
              },
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => commit(),
          ),
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(error!, style: TextStyle(color: colors.error)),
        ),
    ];
    void close() {
      if (commit()) widget.onClose();
    }

    final player = widget.player;
    if (player == null) {
      return SidePanel(
        title: 'Add player',
        onClose: close,
        children: [
          ...fields,
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(onPressed: commit, child: const Text('Add')),
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
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
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
        if (p.withdrawn)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Withdrawn', style: muted),
          ),
        ...fields,
        if (dirty)
          Row(
            children: [
              FilledButton(onPressed: commit, child: const Text('Save')),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(load),
                child: const Text('Revert'),
              ),
            ],
          ),
        heading('US Chess'),
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
            const SizedBox(height: 10),
            Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              [
                'Membership ${m.status ?? 'unknown'}',
                if (m.expiration != null) 'expires ${m.expiration}',
              ].join(' · '),
              style: muted,
            ),
            const SizedBox(height: 6),
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
                      avatar: r.value == p.rating
                          ? const Icon(Icons.check, size: 16)
                          : null,
                      label: Text('${r.key} ${r.value}'),
                      tooltip: 'Use this rating for pairings',
                      onPressed: r.value == p.rating
                          ? null
                          : () => applyMember(
                              m,
                              (player) =>
                                  c.savePlayer(player.copy(rating: r.value)),
                            ),
                    ),
              ],
            ),
          ],
        ],
        if (open.isNotEmpty) ...[
          heading('Byes'),
          for (final r in open)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
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
                        ButtonSegment(value: 1, label: Text('½')),
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
              'Rounds have been played. Games and points stay with the player, and the section continues with Swiss pairings.',
              style: muted,
            ),
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
                FilledButton(onPressed: confirmMove, child: const Text('Move')),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() {
                    moveTo = null;
                    reason.clear();
                  }),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ],
        heading('Pairing requests'),
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
            padding: const EdgeInsets.only(bottom: 6),
            child: InputChip(
              label: Text(other.name),
              onDeleted: () =>
                  attempt(() => c.avoidPair(p.id, other.id, false)),
              deleteButtonTooltipMessage: 'Allow pairing with ${other.name}',
            ),
          ),
        DropdownButton<String>(
          key: const ValueKey('avoid-player'),
          isExpanded: true,
          hint: const Text('Choose a player to avoid…'),
          items: [
            for (final other in e.players.where(
              (other) => other.id != p.id && !p.avoid.contains(other.id),
            ))
              DropdownMenuItem(
                value: other.id,
                child: Text(other.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            if (id != null) attempt(() => c.avoidPair(p.id, id, true));
          },
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

enum _Side { player, add, paste }

/// Keeps tables compact and reserves a details column on wide windows.
class PlayerDetailsLayout extends StatelessWidget {
  const PlayerDetailsLayout({required this.child, this.panel, super.key});
  final Widget child;
  final Widget? panel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final reserve = panel != null || constraints.maxWidth >= 1120;
      final contentWidth = (constraints.maxWidth - (reserve ? 360 : 0)).clamp(
        360.0,
        1100.0,
      );
      // Small windows can scroll across the table and details together.
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth < contentWidth + (reserve ? 360 : 0)
              ? contentWidth + (reserve ? 360 : 0)
              : constraints.maxWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: contentWidth, child: child),
              const Spacer(),
              if (reserve)
                SizedBox(
                  key: const ValueKey('player-details-area'),
                  width: 360,
                  child: panel == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(top: 20),
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
    super.key,
  });
  final String title;
  final VoidCallback onClose;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
      child: Container(
        width: 360,
        margin: const EdgeInsets.fromLTRB(0, 0, 20, 16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          border: Border.all(color: colors.outlineVariant),
        ),
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pastes spreadsheet rows as players. The text is kept as a draft until
/// it imports.
class _PastePanel extends StatefulWidget {
  const _PastePanel({required this.controller, required this.onClose});
  final TournamentController controller;
  final VoidCallback onClose;
  @override
  State<_PastePanel> createState() => _PastePanelState();
}

class _PastePanelState extends State<_PastePanel> {
  late final text = TextEditingController(
    text: widget.controller.repository.readPreference('import-draft') ?? '',
  );
  String? summary, error;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void save() {
    final c = widget.controller;
    try {
      final result = importRoster(c, text.text);
      c.repository.writePreference('import-draft', '');
      text.clear();
      setState(() {
        summary = result;
        error = null;
      });
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SidePanel(
      title: 'Paste players',
      onClose: widget.onClose,
      children: [
        Text(
          'Paste rows from a spreadsheet: Name, US Chess ID, Rating. Players already in the event are not duplicated.',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('paste-roster'),
          controller: text,
          autofocus: true,
          minLines: 10,
          maxLines: 20,
          decoration: const InputDecoration(
            hintText: 'Name,ID,Rating\nMorgan Lee,12345678,1650',
          ),
          onChanged: (v) {
            try {
              widget.controller.repository.writePreference('import-draft', v);
            } catch (_) {
              // A lost draft only matters after a crash.
            }
          },
        ),
        const SizedBox(height: 12),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(onPressed: save, child: const Text('Import')),
        ),
        if (summary != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(summary!),
                TextButton(
                  onPressed: () {
                    widget.controller.undo();
                    setState(() => summary = null);
                  },
                  child: const Text('Undo'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
