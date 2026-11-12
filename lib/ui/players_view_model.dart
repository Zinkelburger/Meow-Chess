import 'dart:collection';
import 'dart:math' as math;

import '../domain/fide.dart';
import '../domain/model.dart';
import '../domain/pairing.dart';
import '../domain/standings.dart';
import 'player_format.dart';
import 'result_format.dart';

// The rules behind the Players page and the crosstable, kept apart from
// their widgets so they can be tested without pumping one: which players
// are ticked, what the column beside the table shows, which rows are
// listed and in what order, and where the arrow keys go between score
// cells.

/// What the right-hand column shows beside the table, so the list stays in
/// view. A player's card saves its field edits on Enter, on Save, when
/// another player is opened and when the card closes; byes, section and
/// withdrawal apply at once. The names are saved with the view.
enum PlayersSide {
  newSection,
  player,
  add,
  paste,
  team,
  selection,
  ratingReview,
  done,
}

/// Where the column returns when a panel closes: the ticked players'
/// actions, then an open rating review, then nothing.
PlayersSide? restingSideFor({required bool ticked, required bool reviewing}) =>
    ticked
    ? PlayersSide.selection
    : reviewing
    ? PlayersSide.ratingReview
    : null;

/// The column a saved view reopens with: never a confirmation already
/// seen, a rating review that has ended, or actions for nobody ticked.
PlayersSide? restoredSide(
  PlayersSide? saved, {
  required bool reviewing,
  required bool ticked,
}) =>
    saved == PlayersSide.done ||
        (saved == PlayersSide.ratingReview && !reviewing) ||
        (saved == PlayersSide.selection && !ticked)
    ? null
    : saved;

/// Whether the column changes once the ticks have changed, and to what:
/// ticking shows what can be done with the ticked players, unless a form
/// is open, and unticking the last one closes those actions.
({bool change, PlayersSide? side}) sideAfterTicking(
  PlayersSide? side, {
  required bool ticked,
  required PlayersSide? resting,
}) {
  if (!ticked) {
    return side == PlayersSide.selection
        ? (change: true, side: resting)
        : (change: false, side: side);
  }
  return side == null ||
          side == PlayersSide.selection ||
          side == PlayersSide.ratingReview ||
          side == PlayersSide.done
      ? (change: true, side: PlayersSide.selection)
      : (change: false, side: side);
}

/// The ticked players, and a move or swap that was reviewed for them. One
/// click must never confirm a pending move or swap for a different group,
/// so changing the ticks drops it.
class PlayerSelection {
  final _ticked = <String>{};

  /// The ticked players, read-only: ticks change only through [tick],
  /// [clear] and [keepOnly], which drop a pending move or swap with them.
  /// The same view lives as long as the selection, since the row menu
  /// acts on it.
  late final Set<String> ticked = UnmodifiableSetView(_ticked);

  /// The row last ticked or unticked by hand, where a Shift-click range
  /// starts.
  String? anchor;

  /// A move of the ticked players waiting for a reason.
  String? moveTo;

  /// The revision the move or swap was reviewed at.
  int? moveRevision;
  bool swapping = false;

  /// Ticks or unticks [ids].
  void tick(Iterable<String> ids, bool value) {
    final before = _ticked.length;
    value ? _ticked.addAll(ids) : _ticked.removeAll(ids);
    if (_ticked.length != before) dropPending();
  }

  /// The rows a click on [id] ticks or unticks: with Shift, every row in
  /// [order] from the [anchor] to it; otherwise that row alone.
  List<String> clickRange(
    List<String> order,
    String id, {
    required bool shift,
  }) {
    final from = anchor == null ? -1 : order.indexOf(anchor!);
    final to = order.indexOf(id);
    if (shift && from >= 0 && to >= 0) {
      return order.sublist(math.min(from, to), math.max(from, to) + 1);
    }
    return [id];
  }

  /// Forgets a pending move or swap.
  void dropPending() {
    moveTo = null;
    swapping = false;
  }

  /// Unticks everyone after acting on them.
  void clear() {
    _ticked.clear();
    dropPending();
  }

  /// Unticks players who are no longer in the event, as after Undo.
  void keepOnly(Iterable<Player> players) {
    final ids = {for (final p in players) p.id};
    final before = _ticked.length;
    _ticked.removeWhere((id) => !ids.contains(id));
    if (_ticked.length != before) dropPending();
  }
}

/// Whether [p] matches the search [query]: by name, US Chess ID or team.
bool playerMatches(Player p, String query) {
  final q = query.trim().toLowerCase();
  return q.isEmpty ||
      p.name.toLowerCase().contains(q) ||
      p.memberId.contains(q) ||
      p.team.toLowerCase().contains(q);
}

/// Each player's pairing number in [s]: their place on the section's list,
/// which is what the pairing engine, the wall chart and the printed player
/// list number them by. A FIDE-rated Swiss numbers by its FIDE pairing order
/// instead (C.04.2). Results, sorting and searching never change it.
Map<String, int> pairingNumbers(Event e, Section s) => {
  for (final (i, id)
      in (s.fideRated && pairingFormat(s) == Format.swiss
              ? [for (final p in fidePairingOrder(e, s)) p.id]
              : s.players)
          .indexed)
    id: i + 1,
};

/// The rows of the players table or crosstable, worked out once a build.
class RosterLayout {
  const RosterLayout({
    required this.groups,
    required this.tables,
    required this.numbers,
    required this.ranks,
    required this.order,
    required this.cellGames,
    required this.rounds,
    required this.started,
    required this.prizeSection,
    required this.tiebreakColumns,
  });

  /// Each section listed with its matching players, then (with every
  /// section on screen) the players not in a section; null for those.
  final List<(Section?, List<Player>)> groups;

  /// Each paired section's standings, by player.
  final Map<String, Map<String, Standing>> tables;

  /// Pairing numbers and places, over whole sections whatever is listed.
  final Map<String, int> numbers, ranks;

  /// Players in on-screen order, for arrow-key movement.
  final List<Player> order;

  /// The games each listed player has a score cell for, rounds left to
  /// right: where Left and Right move.
  final Map<String, List<Game>> cellGames;

  /// Round columns in the crosstable; none on the Players page.
  final int rounds;

  /// Play has started in a section of the crosstable: rows are in
  /// standings order with points.
  final bool started;

  /// The section ranked plays a fixed schedule, so prize standings apply.
  final bool prizeSection;

  /// The posted tie-break methods shown beside the points, in order, once
  /// the event ranks by them.
  final List<TiebreakMethod> tiebreakColumns;

  /// How many players are listed.
  int get shown => groups.fold(0, (int n, g) => n + g.$2.length);
}

/// Lays out the players of [e] in section [sectionId] (every section when
/// null). The crosstable ([standingsOnly]) ranks a paired section by its
/// standings, [prizeStandings] leaving out early round-robin withdrawals.
/// Only players matching [query] are listed. While a result is being
/// entered the rows keep the [entryOrder] they had, so a score never moves
/// the row under the cursor.
RosterLayout layoutRoster(
  Event e, {
  required String? sectionId,
  required bool standingsOnly,
  required String query,
  required bool prizeStandings,
  List<String>? entryOrder,
}) {
  bool viewed(Section s) => sectionId == null || s.id == sectionId;
  // Roster setup stays separate from the crosstable on the Pairings page.
  final started =
      standingsOnly && e.sections.any((s) => s.rounds.isNotEmpty && viewed(s));
  final ranked = started;
  final rankedSection = e.sections
      .where((s) => s.rounds.isNotEmpty && viewed(s))
      .firstOrNull;
  final tiebreakColumns = started && e.useTiebreaks && rankedSection != null
      ? standingsTiebreaks(e, rankedSection)
      : const <TiebreakMethod>[];
  // Rule 30B: a round-robin player who withdrew before half their games
  // leaves the prize standings.
  final prizeSection = rankedSection != null && hasFixedSchedule(rankedSection);
  final tables = <String, Map<String, Standing>>{
    for (final s in e.sections)
      if (s.rounds.isNotEmpty)
        s.id: {
          for (final row in standings(
            e,
            s,
            forPrizes: prizeStandings && prizeSection && hasFixedSchedule(s),
          ))
            row.player.id: row,
        },
  };
  final numbers = <String, int>{}, ranks = <String, int>{};
  // While a result is entered each row keeps its place on the frozen list;
  // a row not on it goes first. Ties keep the order the rows came in.
  final frozen = entryOrder == null
      ? null
      : {for (final (i, id) in entryOrder.indexed) id: i};
  void holdOrder(List<Player> players, [int Function(Player, Player)? then]) {
    if (frozen == null && then == null) return;
    final came = {for (final (i, p) in players.indexed) p.id: i};
    players.sort((a, b) {
      var by = frozen == null
          ? 0
          : (frozen[a.id] ?? -1).compareTo(frozen[b.id] ?? -1);
      if (by == 0 && then != null) by = then(a, b);
      return by != 0 ? by : came[a.id]!.compareTo(came[b.id]!);
    });
  }

  List<Player> ordered(Section s) {
    final table = tables[s.id];
    final players = ranked && table != null
        ? [
            for (final row in table.values) row.player,
            for (final id in s.players)
              if (!table.containsKey(id)) e.player(id),
          ]
        : s.players.map(e.player).toList();
    // Numbers and places cover the whole section, whatever a search or
    // the order held during result entry shows of it.
    numbers.addAll(pairingNumbers(e, s));
    if (ranked && table != null) {
      for (final (i, id) in table.keys.indexed) {
        ranks[id] = i + 1;
      }
    }
    final listed = players.where((p) => playerMatches(p, query)).toList();
    holdOrder(listed);
    return listed;
  }

  List<Player> unassigned() {
    final listed = e.players
        .where((p) => e.sectionOf(p.id) == null && playerMatches(p, query))
        .toList();
    // Highest rated first, under any order held during result entry.
    holdOrder(listed, (a, b) => b.rating.compareTo(a.rating));
    return listed;
  }

  final groups = <(Section?, List<Player>)>[
    for (final s in e.sections)
      if (viewed(s)) (s, ordered(s)),
    if (sectionId == null) (null, unassigned()),
  ].where((g) => g.$2.isNotEmpty || (g.$1 != null && query.isEmpty)).toList();
  final rounds = !standingsOnly
      ? 0
      : groups
            .map((g) => g.$1?.plannedRounds ?? 0)
            .fold(0, (int a, b) => a > b ? a : b);
  return RosterLayout(
    groups: groups,
    tables: tables,
    numbers: numbers,
    ranks: ranks,
    order: [for (final g in groups) ...g.$2],
    cellGames: {
      if (standingsOnly)
        for (final (s, players) in groups)
          if (s != null && s.format != Format.knockout)
            for (final p in players)
              p.id: [
                for (var r = 1; r <= s.rounds.length && r <= rounds; r++)
                  if (r <= s.plannedRounds) ...gamesOf(s, r, p.id),
              ],
    },
    rounds: rounds,
    started: started,
    prizeSection: prizeSection,
    tiebreakColumns: tiebreakColumns,
  );
}

/// [playerId]'s games in round [round] of [s], as the round lists them:
/// none when that round is not posted or the player has a bye in it.
List<Game> gamesOf(Section s, int round, String playerId) => [
  for (final g
      in s.rounds.where((r) => r.number == round).firstOrNull?.games ??
          const <Game>[])
    if (g.white == playerId || g.black == playerId) g,
];

/// Fixed column widths, before text scaling, keep the table narrow and
/// aligned.
abstract final class RosterColumns {
  static const check = 40.0,
      rank = 40.0,
      number = 28.0,
      name = 200.0,
      rating = 64.0,
      preview = 132.0,
      proposal = 192.0,
      uscfName = 200.0,
      membership = 216.0,
      note = 240.0,
      id = 100.0,
      round = 40.0,
      points = 40.0,
      tiebreak = 56.0;
}

/// Which columns the players table or crosstable shows, worked out once a
/// build so the column header, each section's header, every row and the
/// table's width all agree.
final class ShownColumns {
  const ShownColumns({
    required this.checkbox,
    required this.scores,
    required this.wideName,
    required this.ids,
    required this.rating,
    required this.fide,
    required this.review,
    required this.ratingPreview,
    required this.membership,
    required this.note,
    required this.rounds,
    required this.tiebreaks,
  });

  /// The columns of the crosstable ([standingsOnly]) or the Players page.
  /// [checkboxes]: the view has its own column beside the table, where the
  /// ticked players' actions show; a crosstable embedded in Pairings opens
  /// players in its parent instead, so it has no tick boxes and stays one
  /// Tab stop. [started]: play has begun in a section shown, so rows are
  /// ranked with points. [reviewing]: a US Chess rating review is open. [showIds] is the
  /// TD's choice, [usChessView] that something listed is US Chess rated and
  /// [fideListed] that something listed is FIDE rated.
  factory ShownColumns.of({
    required bool standingsOnly,
    required bool checkboxes,
    required bool started,
    required bool reviewing,
    required bool ratingPreview,
    required bool showIds,
    required bool usChessView,
    required bool fideListed,
    required int rounds,
    required List<TiebreakMethod> tiebreaks,
  }) {
    // The roster columns are for setting up, not for the crosstable.
    final roster = !standingsOnly;
    return ShownColumns(
      checkbox: checkboxes,
      scores: started,
      wideName: roster,
      // A rating review compares IDs, so it always shows them.
      ids: roster && (reviewing || (showIds && usChessView)),
      rating: roster && (usChessView || reviewing),
      fide: roster && fideListed,
      review: reviewing,
      ratingPreview: ratingPreview,
      membership: roster && usChessView,
      note: roster,
      rounds: rounds,
      tiebreaks: started ? tiebreaks : const [],
    );
  }

  /// The tick box, before everything else.
  final bool checkbox;

  /// Rank before the number, then points and [tiebreaks] after the rounds.
  final bool scores;

  /// The Players page gives names more room than the crosstable.
  final bool wideName;

  /// US Chess ID, US Chess rating, and FIDE ID with the FIDE rating.
  final bool ids, rating, fide;

  /// The proposed US Chess rating and the US Chess name, during a review.
  final bool review;
  final bool ratingPreview;

  /// US Chess membership expiry, and the registration note.
  final bool membership, note;

  /// Round columns; none on the Players page.
  final int rounds;
  final List<TiebreakMethod> tiebreaks;

  /// The table's width before text scaling.
  double get width =>
      (checkbox ? RosterColumns.check : 0) +
      (scores ? RosterColumns.rank : 0) +
      RosterColumns.number +
      (wideName ? RosterColumns.name : 160) +
      (ids ? RosterColumns.id : 0) +
      (rating ? RosterColumns.rating : 0) +
      (fide ? RosterColumns.id + RosterColumns.rating : 0) +
      (review ? RosterColumns.proposal + RosterColumns.uscfName : 0) +
      (ratingPreview ? RosterColumns.preview : 0) +
      (membership ? RosterColumns.membership : 0) +
      (note ? RosterColumns.note : 0) +
      rounds * RosterColumns.round +
      (scores ? RosterColumns.points : 0) +
      tiebreaks.length * RosterColumns.tiebreak +
      28;
}

/// The score cells of [round], top to bottom: each listed player's games
/// that round, in [order]. Up, Down and Enter move through them.
List<(Player, Game)> roundCells(
  List<Player> order,
  Event pairingEvent,
  int round,
) => [
  for (final p in order)
    if (pairingEvent.sectionOf(p.id) case final section?)
      for (final g in gamesOf(section, round, p.id)) (p, g),
];

/// Where [player]'s cell for [gameId] is among [cells]; -1 when it is not.
int cellIndex(List<(Player, Game)> cells, String player, String gameId) =>
    cells.indexWhere((x) => x.$1.id == player && x.$2.id == gameId);

/// What [p]'s cell for round [r] of [s] says, and its tooltip: a bye's
/// mark, or a dash before pairing; a game's opponent, colour and result,
/// or that it has none yet. Played games show score boxes, so only a bye
/// needs a mark. Opponents are looked up in [e].
(String, String) roundCellText(Event e, Player p, Section? s, int r) {
  final played = s != null && r <= s.rounds.length;
  final bye = played ? null : p.byes[r];
  return played
      ? _playedText(e, s, r, p.id)
      : bye != null
      ? (byeMark(bye), 'Round $r: ${halves(bye)}-point bye requested')
      : ('—', 'Round $r: not paired yet.');
}

/// A posted round's bye mark, and a tooltip naming each opponent.
(String, String) _playedText(Event e, Section s, int number, String pid) {
  final round = s.rounds.where((r) => r.number == number).firstOrNull;
  if (round == null) return ('', '');
  final bye = round.byes.where((b) => b.player == pid).firstOrNull;
  if (bye != null) {
    return (byeMark(bye.points), 'Round $number: ${bye.reason}');
  }
  final games = gamesOf(s, number, pid);
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

/// The focus key of [player]'s score cell for [gameId].
String cellKey(String gameId, String player) => '$gameId-$player';

/// The one score cell Tab enters the crosstable at, among the cells of the
/// players in [order] ([cellGames]): the [active] one while it is listed,
/// else the first missing a result, else the first. Null when there are no
/// cells.
String? entryCellFor(
  List<Player> order,
  Map<String, List<Game>> cellGames,
  String? active,
) {
  String? first, missing;
  for (final p in order) {
    for (final g in cellGames[p.id] ?? const <Game>[]) {
      final key = cellKey(g.id, p.id);
      if (key == active) return key;
      first ??= key;
      if (!g.outcome.resolved) missing ??= key;
    }
  }
  return missing ?? first;
}

/// After a result in cell [index] of [cells]: the next cell still missing a
/// result, wrapping round, by the results now in [outcomeOf].
(Player, Game)? nextMissingCell(
  List<(Player, Game)> cells,
  int index,
  String gameId,
  Outcome Function(String gameId) outcomeOf,
) => [
  ...cells.skip(index + 1),
  ...cells.take(index),
].where((x) => x.$2.id != gameId && !outcomeOf(x.$2.id).resolved).firstOrNull;

/// A key on a crosstable score cell, as the cells read it.
enum CellKey {
  up,
  down,
  left,
  right,
  enter,

  /// Space: the player's details.
  details,
  other;

  bool get arrow => this == up || this == down || this == left || this == right;
}

/// The facts about one key event that decide what a score cell does.
class CellKeyPress {
  const CellKeyPress(
    this.key, {
    this.release = false,
    this.repeat = false,
    this.modified = false,
    this.shift = false,
    this.outcome,
    this.printable = false,
  });
  final CellKey key;

  /// A key coming up, or held down.
  final bool release, repeat;

  /// Control, Command or Alt is held.
  final bool modified;
  final bool shift;

  /// The result the key enters for the cell's player, if it is a result key.
  final Outcome? outcome;

  /// The key types a visible character.
  final bool printable;

  /// Not a key the cell takes, so it goes on to the shortcuts above: a key
  /// coming up, one held with Control, Command or Alt, or a held key that
  /// is not an arrow. Holding an arrow keeps moving; holding a result key
  /// enters it once. The board grid beside the crosstable swallows any
  /// other held key; the crosstable lets it pass on.
  bool get passesOn => release || modified || (repeat && !key.arrow);
}

/// What a key on a score cell does.
sealed class CellKeyAction {
  const CellKeyAction();
}

/// Not the cell's key: it goes on to the shortcuts above.
final class CellKeyIgnored extends CellKeyAction {
  const CellKeyIgnored();
}

/// Taken, and nothing happens: an arrow at the edge, or a result key while
/// one is being saved.
final class CellKeySwallowed extends CellKeyAction {
  const CellKeySwallowed();
}

/// Focus moves to [player]'s cell for [game].
final class CellMove extends CellKeyAction {
  const CellMove(this.player, this.game);
  final String player;
  final Game game;
}

final class CellShowPlayer extends CellKeyAction {
  const CellShowPlayer();
}

/// A printable key that is not a result: say which keys are.
final class CellRefuse extends CellKeyAction {
  const CellRefuse();
}

/// A result key: takes down a "not a result key" hint, and enters
/// [outcome] unless another result is still being saved ([save] false).
final class CellEnter extends CellKeyAction {
  const CellEnter(this.outcome, {required this.save});
  final Outcome outcome;
  final bool save;
}

/// What [press] does on [player]'s cell for [game]. Up, Down and Enter move
/// through the round's [cells] (Shift goes up); Left and Right move to the
/// same player's game in the round before or after, among [games]. Holding
/// an arrow keeps moving; holding a result key enters it once. Nothing is
/// saved while [entering] another result.
CellKeyAction cellKeyAction(
  CellKeyPress press, {
  required String player,
  required Game game,
  required List<(Player, Game)> cells,
  required List<Game> games,
  required bool entering,
}) {
  if (press.passesOn) return const CellKeyIgnored();
  final index = cellIndex(cells, player, game.id);
  if (press.key == CellKey.up ||
      press.key == CellKey.down ||
      press.key == CellKey.enter) {
    final next = index + (press.key == CellKey.up || press.shift ? -1 : 1);
    return next >= 0 && next < cells.length
        ? CellMove(cells[next].$1.id, cells[next].$2)
        : const CellKeySwallowed();
  }
  if (press.key.arrow) {
    final at = games.indexWhere((g) => g.id == game.id);
    final next = at + (press.key == CellKey.left ? -1 : 1);
    return at >= 0 && next >= 0 && next < games.length
        ? CellMove(player, games[next])
        : const CellKeySwallowed();
  }
  if (press.key == CellKey.details) return const CellShowPlayer();
  final outcome = press.outcome;
  if (outcome == null) {
    return press.printable ? const CellRefuse() : const CellKeyIgnored();
  }
  return CellEnter(outcome, save: !entering);
}

/// What the players table or crosstable remembers between visits, saved as
/// a map whose keys and order stay as older versions wrote them.
class SavedPlayersView {
  const SavedPlayersView({
    this.search = '',
    this.open,
    this.side,
    this.selected = const [],
    this.activeResult,
    this.showRatingPreview = false,
    this.prizeStandings = false,
    this.moveTo,
    this.moveRevision,
    this.swapping = false,
    this.moveReason = '',
    this.scroll = 0,
  });

  /// Reads a saved map, as older versions wrote it too. The scroll offset
  /// is read with [scrollOf] once the table is laid out.
  factory SavedPlayersView.fromMap(
    Map<String, dynamic> saved,
  ) => SavedPlayersView(
    search: saved['search'] as String? ?? '',
    open: saved['open'] as String?,
    side: PlayersSide.values.where((v) => v.name == saved['side']).firstOrNull,
    selected: (saved['selected'] as List? ?? []).whereType<String>().toList(),
    activeResult: saved['activeResult'] as String?,
    showRatingPreview: saved['showRatingPreview'] == true,
    prizeStandings: saved['prizeStandings'] == true,
    moveTo: saved['moveTo'] as String?,
    moveRevision: (saved['moveRevision'] as num?)?.toInt(),
    swapping: saved['swapping'] == true,
    moveReason: saved['moveReason'] as String? ?? '',
  );

  static double scrollOf(Map<String, dynamic> saved) =>
      (saved['scroll'] as num? ?? 0).toDouble();

  final String search;
  final String? open;
  final PlayersSide? side;
  final List<String> selected;
  final String? activeResult;
  final bool showRatingPreview, prizeStandings;
  final String? moveTo;
  final int? moveRevision;
  final bool swapping;
  final String moveReason;
  final double scroll;

  /// The revision is kept only while a move or swap waits on it.
  Map<String, Object?> toMap() => {
    'search': search,
    'open': open,
    'side': side?.name,
    'selected': selected,
    'activeResult': activeResult,
    'showRatingPreview': showRatingPreview,
    'prizeStandings': prizeStandings,
    'moveTo': moveTo,
    'moveRevision': moveTo != null || swapping ? moveRevision : null,
    'swapping': swapping,
    'moveReason': moveReason,
    'scroll': scroll,
  };
}
