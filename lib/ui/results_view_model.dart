import 'dart:math' as math;

import '../domain/model.dart';
import '../domain/pairing.dart';
import 'result_format.dart';

// The rules behind the Pairings page's board sheet, kept apart from its
// widgets so they can be tested without pumping one: which rounds are on
// screen, which boards are listed and in what order, where the cursor goes
// next, what a key on a score box does, and the words the sheet shows.

/// One game on the sheet, with the section and round it belongs to.
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

/// One player's score box, as focus and the saved view name it:
/// '$gameId-w' or '$gameId-b'.
String boxKey(String gameId, bool white) => '$gameId-${white ? 'w' : 'b'}';

/// An earlier round, whose results change only while correcting.
bool isEarlierRound(Section s, Round r) =>
    s.format == Format.swiss && r.number < s.rounds.length;

/// Which rounds the sheet shows, and whether an earlier round's results may
/// be changed.
class RoundSelection {
  /// An earlier round on screen; null shows each section's current round.
  int? selectedRound;
  bool showAllRounds = false;

  /// The default view: a fixed quad schedule shows every round, while
  /// Swiss sections beside it stay on their current round.
  bool scheduleRounds = true;

  /// Whether results in an earlier round may be changed.
  bool correcting = false;

  /// A result key was pressed on a read-only round.
  bool nudged = false;

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

  /// A board of an earlier round, while not correcting.
  bool locked(BoardRow row) =>
      isEarlierRound(row.section, row.round) && !correcting;

  /// Shows round [n], or the current round when [n] is the [latest].
  void pick(int? n, int latest) {
    selectedRound = n == latest ? null : n;
    showAllRounds = scheduleRounds = false;
    correcting = nudged = false;
  }

  void showAll() {
    showAllRounds = true;
    selectedRound = null;
    correcting = nudged = false;
  }

  void startCorrecting() {
    correcting = true;
    nudged = false;
  }

  void stopCorrecting() => correcting = nudged = false;

  /// A round was posted or undone: back to the current round, or to every
  /// round when [allQuads].
  void reset({required bool allQuads}) {
    selectedRound = null;
    showAllRounds = allQuads;
    scheduleRounds = true;
    correcting = nudged = false;
  }

  /// Forgets a selected round that is no longer there, as after Undo.
  void keepWithin(Iterable<int> roundNumbers) {
    if (selectedRound != null && !roundNumbers.contains(selectedRound)) {
      selectedRound = null;
    }
  }
}

/// Every board of [sections] on screen under [selection], by round, board
/// and game.
List<BoardRow> boardRows(Iterable<Section> sections, RoundSelection selection) {
  final result = <BoardRow>[];
  for (final s in sections) {
    for (final r in selection.shownRounds(s)) {
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

/// Whether [p]'s name holds the search [query]; no search names everyone.
bool nameMatches(Player p, String query) {
  final q = query.trim().toLowerCase();
  return q.isEmpty || p.name.toLowerCase().contains(q);
}

/// The [rows] listed: only those without a result under [missingOnly], and
/// only the board numbered [query] or those whose player's name holds it.
List<BoardRow> filterBoardRows(
  List<BoardRow> rows,
  Event e, {
  required String query,
  required bool missingOnly,
}) {
  final q = query.trim();
  return rows
      .where(
        (r) =>
            (!missingOnly || !r.game.outcome.resolved) &&
            (q.isEmpty ||
                '${r.game.board}' == q ||
                nameMatches(e.player(r.game.white), query) ||
                nameMatches(e.player(r.game.black), query)),
      )
      .toList();
}

/// One line of the board sheet.
sealed class SheetItem {
  const SheetItem();
}

/// A section's name, and its round when every round is on screen.
final class SheetHeading extends SheetItem {
  const SheetHeading(this.section, this.round);
  final Section section;
  final Round round;
}

/// The score the boards below it start from.
final class SheetScoreGroup extends SheetItem {
  const SheetScoreGroup(this.points);
  final int points;
}

/// A board, with each player's score before the round when grouped.
final class SheetBoard extends SheetItem {
  const SheetBoard(this.row, this.before);
  final BoardRow row;
  final Map<String, int>? before;
}

/// A bye, listed after the boards of its round. [every] keys it by round
/// as well, since every round is on screen.
final class SheetBye extends SheetItem {
  const SheetBye(this.bye, this.round, {required this.every});
  final ByeAward bye;
  final int round;
  final bool every;
}

/// The lines of the board sheet, and where each board's game sits among
/// them, so the cursor can jump to a board the lazy list has not built.
class SheetLayout {
  const SheetLayout(this.items, this.itemOf);
  final List<SheetItem> items;
  final Map<String, int> itemOf;

  /// No boards: a jump must not use positions from the last sheet drawn.
  static const empty = SheetLayout([], {});
}

/// Lays out the [visible] boards of the rounds [shown]: rounds in order,
/// each section's boards from its first board, under the section's name
/// when [everySection] is on screen or every round of it is, split into
/// score groups once a Swiss round has scores, then the byes that match the
/// search [query] (none under [missingOnly]).
SheetLayout layoutSheet({
  required Event event,
  required List<(Section, Round)> shown,
  required List<BoardRow> visible,
  required RoundSelection selection,
  required bool everySection,
  required bool missingOnly,
  required String query,
}) {
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
  final items = <SheetItem>[];
  final itemOf = <String, int>{};
  for (final (s, r) in ordered) {
    final boards = bySection[(s.id, r.number)] ?? const <BoardRow>[];
    final byes = missingOnly
        ? const <ByeAward>[]
        : r.byes
              .where((b) => nameMatches(event.player(b.player), query))
              .toList();
    if (boards.isEmpty && byes.isEmpty) continue;
    if (everySection || selection.allRoundsOf(s)) {
      items.add(SheetHeading(s, r));
    }
    // Swiss boards fall into score groups once anyone has a score.
    final before = s.format == Format.swiss && r.number > 1
        ? scoresBefore(s, r.number)
        : null;
    int group(Game g) => math.max(before?[g.white] ?? 0, before?[g.black] ?? 0);
    final grouped =
        before != null && boards.map((b) => group(b.game)).toSet().length > 1;
    int? last;
    for (final row in boards) {
      if (grouped && group(row.game) != last) {
        final points = last = group(row.game);
        items.add(SheetScoreGroup(points));
      }
      itemOf[row.game.id] = items.length;
      items.add(SheetBoard(row, before));
    }
    for (final b in byes) {
      items.add(SheetBye(b, r.number, every: selection.allRoundsOf(s)));
    }
  }
  return SheetLayout(items, itemOf);
}

/// Where the cursor starts: the first board without a result, or the first
/// board when every one has a result.
BoardRow? firstOpenRow(List<BoardRow> visible) =>
    visible.where((r) => !r.game.outcome.resolved).firstOrNull ??
    visible.firstOrNull;

/// The one box Tab enters the grid at: the [activeBox] while its board is
/// listed, otherwise White's box on the first board without a result.
String? entryBoxFor(List<BoardRow> visible, String? activeBox) {
  final keys = {
    for (final r in visible) ...[
      boxKey(r.game.id, true),
      boxKey(r.game.id, false),
    ],
  };
  final start = firstOpenRow(visible);
  return keys.contains(activeBox)
      ? activeBox
      : start == null
      ? null
      : boxKey(start.game.id, true);
}

/// The game [by] boards up or down from [gameId], stopping at either end.
/// Null when nothing is listed.
String? stepFrom(List<BoardRow> visible, String gameId, int by) {
  if (visible.isEmpty) return null;
  final i = visible.indexWhere((r) => r.game.id == gameId);
  return visible[(i + by).clamp(0, visible.length - 1)].game.id;
}

/// After a result on [gameId]: the next game in [order] still missing one
/// among [rows], wrapping to an earlier skipped game. Null when none is.
String? nextOpenGame(
  List<String> order,
  Iterable<BoardRow> rows,
  String gameId,
) {
  final open = {
    for (final r in rows)
      if (!r.game.outcome.resolved) r.game.id,
  };
  final i = order.indexOf(gameId);
  return [
    ...order.skip(i + 1),
    ...order.take(math.max(i, 0)),
  ].where(open.contains).firstOrNull;
}

/// A key on a score box, as the grid reads it.
enum GridKey {
  up,
  down,
  left,
  right,
  enter,

  /// A: assume a result for pairing.
  assume,

  /// Space: the player's details.
  details,

  /// F2: an explicit correction.
  correct,

  /// Delete or Backspace.
  clear,
  other;

  bool get arrow => this == up || this == down || this == left || this == right;
}

/// The facts about one key event that decide what the grid does with it.
class GridKeyPress {
  const GridKeyPress(
    this.key, {
    this.release = false,
    this.repeat = false,
    this.modified = false,
    this.shift = false,
    this.outcome,
    this.drawAttempt = false,
    this.printable = false,
    this.refusedOnForfeit = false,
  });
  final GridKey key;

  /// A key coming up, or held down.
  final bool release, repeat;

  /// Control, Command or Alt is held.
  final bool modified;
  final bool shift;

  /// The result the key enters for the box's player, if it is a result key.
  final Outcome? outcome;

  /// 5, = or a decimal point: someone typing a draw as half a point.
  final bool drawAttempt;

  /// The key types a visible character.
  final bool printable;

  /// A result key with no forfeit meaning, typed on a forfeit board.
  final bool refusedOnForfeit;
}

/// What a key on a score box does.
sealed class GridKeyAction {
  const GridKeyAction();
}

/// Not the grid's key: it goes on to the shortcuts above.
final class GridKeyIgnored extends GridKeyAction {
  const GridKeyIgnored();
}

/// Taken, and nothing happens: a held result key, or a key while saving.
final class GridKeySwallowed extends GridKeyAction {
  const GridKeySwallowed();
}

/// Up or down [by] boards, keeping the side.
final class GridMoveBoard extends GridKeyAction {
  const GridMoveBoard(this.by);
  final int by;
}

/// Across the board, to White's or Black's box.
final class GridMoveSide extends GridKeyAction {
  const GridMoveSide({required this.white});
  final bool white;
}

final class GridAssume extends GridKeyAction {
  const GridAssume();
}

final class GridShowPlayer extends GridKeyAction {
  const GridShowPlayer();
}

final class GridCorrect extends GridKeyAction {
  const GridCorrect();
}

/// Enters [outcome]. [clearsHint] takes down a "not a result key" legend.
final class GridEnter extends GridKeyAction {
  const GridEnter(this.outcome, {required this.clearsHint});
  final Outcome outcome;
  final bool clearsHint;
}

/// A printable key that is not a result: the legend says which keys are,
/// leading with the forfeit rule or the draw key where that is the slip.
final class GridRefuse extends GridKeyAction {
  const GridRefuse({required this.forfeit, required this.draw});
  final bool forfeit, draw;
}

/// What [press] does on a score box whose board has [current] as its result.
/// A [locked] board is an earlier round; nothing is entered while [busy].
GridKeyAction gridKeyAction(
  GridKeyPress press, {
  required bool busy,
  required bool locked,
  required Outcome current,
}) {
  if (press.release) return const GridKeyIgnored();
  // Holding a result key never enters it twice.
  if (press.repeat && !press.key.arrow) return const GridKeySwallowed();
  if (press.modified) return const GridKeyIgnored();
  if (busy) return const GridKeySwallowed();
  switch (press.key) {
    case GridKey.down || GridKey.enter:
      return GridMoveBoard(press.shift ? -1 : 1);
    case GridKey.up:
      return const GridMoveBoard(-1);
    case GridKey.left || GridKey.right:
      return GridMoveSide(white: press.key == GridKey.left);
    case GridKey.assume:
      return !locked && !current.resolved
          ? const GridAssume()
          : const GridKeySwallowed();
    case GridKey.details:
      return const GridShowPlayer();
    case GridKey.correct:
      // An explicit correction, also of an earlier round.
      return current != Outcome.unreported
          ? const GridCorrect()
          : const GridKeySwallowed();
    case GridKey.clear:
      return const GridEnter(Outcome.unreported, clearsHint: false);
    case GridKey.other:
      break;
  }
  final outcome = press.outcome;
  if (outcome == null) {
    // 5, = and the decimal point are answered with the draw key, whether
    // or not the key carries a character (the numpad decimal may not).
    if (press.drawAttempt || press.printable) {
      return GridRefuse(
        forfeit: press.refusedOnForfeit,
        draw: press.drawAttempt,
      );
    }
    return const GridKeyIgnored();
  }
  return GridEnter(outcome, clearsHint: true);
}

/// What replacing the result of [row] did, for the notice with Undo:
/// "Board 7 was 1–0, now ½–½", led by the section when [everySection] is
/// on screen and by the round when more than the current one is.
String overwriteNoticeText(
  BoardRow row,
  Outcome before,
  Outcome now, {
  required bool everySection,
  required bool allRounds,
}) => [
  if (everySection) row.section.name,
  if (allRounds || row.round.number != row.section.rounds.length)
    'Round ${row.round.number}',
  resultChangeText(row.game.board, before, now),
].join(' · ');

/// What is read-only among the rounds on screen, in words: all of it, or
/// only the earlier Swiss rounds, named so the boards beside them are not
/// taken for locked too.
String readOnlyText(
  List<(Section, Round)> shown, {
  required bool everySection,
  required bool showAllRounds,
}) {
  final locked = [
    for (final (s, r) in shown)
      if (isEarlierRound(s, r)) (s, r),
  ];
  if (locked.length == shown.length) return 'Read-only';
  if (locked.length == 1) {
    final (s, r) = locked.single;
    return everySection
        ? '${s.name} round ${r.number} is read-only'
        : 'Round ${r.number} is read-only';
  }
  return showAllRounds
      ? 'Earlier rounds are read-only'
      : '${locked.length} sections are read-only';
}

/// The round heading over the boards: its title, the facts after it, and
/// the round numbers on screen (none before pairing).
({String title, List<String> facts, List<int> numbers}) roundHeading(
  List<(Section, Round)> shown,
  Iterable<Section> sections,
  List<BoardRow> all, {
  required bool showAllRounds,
}) {
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
  return (title: title, facts: facts, numbers: numbers);
}

/// The status line for the focused box: where it is, who is playing, and
/// whose result a key enters, or that the round is read-only.
String entryContext(
  BoardRow row,
  Event e, {
  required bool everySection,
  required bool locked,
  required bool white,
}) => [
  if (everySection) row.section.name,
  'Round ${row.round.number}',
  'Board ${row.game.board}${row.section.doubleGames ? ' · Game ${row.game.leg}' : ''}',
  '${e.player(row.game.white).name} vs ${e.player(row.game.black).name}',
  locked ? 'read-only' : 'entering ${white ? 'White' : 'Black'}\'s result',
].join(' · ');

/// The boards of the round on screen that have not started (no result
/// and no pairing assumption on any of their games), when they can be
/// paired again on their own: one section's latest round, in a US Chess
/// Swiss, with only that section on screen ([singleSection]). Null where
/// that does not apply.
({Section section, Round round, List<int> boards})? repairableRound(
  List<(Section, Round)> shown, {
  required bool singleSection,
}) {
  final only = singleSection ? shown.singleOrNull : null;
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

/// The reason re-pairing starts with: the withdrawal that usually prompts
/// it. Null when nobody on a board not started has withdrawn.
String? suggestedRepairReason(Round round, Event e) {
  final waiting = unstartedBoards(round).toSet();
  final gone = {
    for (final g in round.games.where((g) => waiting.contains(g.board)))
      for (final id in [g.white, g.black])
        if (e.player(id).withdrawn) e.player(id).name,
  };
  return gone.isEmpty ? null : '${gone.join(', ')} withdrew';
}

/// Withdrawn players still sitting at a board that has not started, by
/// name and board, once per board.
List<(String, int)> withdrawnOnUnstarted(Round round, Event e) {
  final waiting = unstartedBoards(round).toSet();
  return [
    for (final g in round.games.where((g) => waiting.contains(g.board)))
      if (g.leg == 1)
        for (final id in [g.white, g.black])
          if (e.player(id).withdrawn) (e.player(id).name, g.board),
  ];
}

/// Editing pairings by clicking players: the first click picks [id],
/// clicking the picked player again cancels, and another player completes
/// the swap with the one [picked] before ([swapWith]).
({String? pick, String? swapWith}) pickForSwap(String? picked, String id) =>
    picked == null || picked == id
    ? (pick: picked == id ? null : id, swapWith: null)
    : (pick: null, swapWith: picked);

/// The games of [round] with players [a] and [b] in each other's places.
/// Two players on one board swap colours.
List<Game> swapInRound(Round round, String a, String b) {
  String swapped(String x) => x == a
      ? b
      : x == b
      ? a
      : x;
  return [
    for (final g in round.games)
      g.copy(white: swapped(g.white), black: swapped(g.black)),
  ];
}

/// What the Pairings page remembers between visits, saved as a map whose
/// keys and order stay as older versions wrote them. It is restored only
/// while the [signature] (each section's round count) is unchanged.
class SavedResultsView {
  const SavedResultsView({
    required this.signature,
    this.round,
    this.allRounds = false,
    this.scheduleRounds = true,
    this.search = '',
    this.box,
    this.scroll = 0,
  });

  /// The view saved in [saved], when it was saved for [signature]; null
  /// once a round has been posted or undone since. Reads what older
  /// versions wrote too.
  static SavedResultsView? restore(
    Map<String, dynamic> saved,
    String signature,
  ) {
    if (saved['signature'] != signature) return null;
    return SavedResultsView(
      signature: signature,
      round: saved['round'] as int?,
      allRounds: saved['allRounds'] == true,
      scheduleRounds: saved['scheduleRounds'] != false,
      search: saved['search'] as String? ?? '',
      box: saved['box'] as String?,
      scroll: (saved['scroll'] as num? ?? 0).toDouble(),
    );
  }

  final String signature;
  final int? round;
  final bool allRounds, scheduleRounds;
  final String search;
  final String? box;
  final double scroll;

  Map<String, Object?> toMap() => {
    'signature': signature,
    'round': round,
    'allRounds': allRounds,
    'scheduleRounds': scheduleRounds,
    'search': search,
    'box': box,
    'scroll': scroll,
  };
}

/// Each section's round count, so a saved view is dropped once a round is
/// posted or undone.
String roundCountSignature(Iterable<Section> sections) =>
    sections.map((s) => '${s.id}:${s.rounds.length}').join('|');
