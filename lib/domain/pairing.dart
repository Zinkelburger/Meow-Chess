import 'dart:math';

import 'fixed_schedule.dart';
import 'model.dart';
import 'bughouse.dart';
import 'fide_pairing.dart';
import 'knockout.dart';
import 'scheveningen.dart';
import 'swiss_pairing.dart';
import 'us_chess.dart';

export 'fixed_schedule.dart';
export 'swiss_pairing.dart'
    show swissPolicy, swissVariations, swissVariationLabels, effectiveColorToss;

List<int> quadGroupSizes(int n) {
  if (n < 4) {
    throw const TournamentException(
      'At least four players are needed. Add a house player or create a section manually.',
    );
  }
  final remainder = n % 4;
  return remainder == 0
      ? List.filled(n ~/ 4, 4)
      : [...List.filled((n - 4 - remainder) ~/ 4, 4), 4 + remainder];
}

/// Quad seeding order: rating high to low, then name (ignoring case and
/// accents), then id.
int quadOrder(Player a, Player b) {
  final c = b.rating.compareTo(a.rating);
  if (c != 0) return c;
  final n = compareNames(a.name, b.name);
  return n != 0 ? n : a.id.compareTo(b.id);
}

/// Groups [players] by rating into quads, with five to seven left over in a
/// small Swiss. Names skip any in [taken], compared case-insensitively.
List<({String name, Format format, List<Player> players})> planQuads(
  Iterable<Player> players, {
  Iterable<String> taken = const [],
}) {
  final pool = players.toList()..sort(quadOrder);
  final used = {for (final name in taken) name.toLowerCase()};
  String free(String Function(int n) name, int from) {
    var n = from;
    while (used.contains(name(n).toLowerCase())) {
      n++;
    }
    used.add(name(n).toLowerCase());
    return name(n);
  }

  var offset = 0;
  return [
    for (final size in quadGroupSizes(pool.length))
      (
        name: size == 4
            ? free((n) => 'Quad $n', 1)
            : free((n) => n == 1 ? 'Bottom Swiss' : 'Bottom Swiss $n', 1),
        format: size == 4 ? Format.quad : Format.swiss,
        players: pool.sublist(offset, offset += size),
      ),
  ];
}

List<Section> makeQuads(Event e, String Function() id) {
  if (e.sections.any((s) => s.rounds.isNotEmpty)) {
    throw const TournamentException(
      'Rounds are already posted. Move or combine entries with an explicit transition instead.',
    );
  }
  final sections = <Section>[];
  var board = 1;
  for (final group in planQuads(e.players.where((p) => !p.withdrawn))) {
    sections.add(
      Section(
        id: id(),
        name: group.name,
        players: [for (final p in group.players) p.id],
        format: group.format,
        boardStart: board,
      ),
    );
    board += (group.players.length + 1) ~/ 2;
  }
  return sections;
}

/// Explicit player requests are independent of team membership.
bool pairingRestricted(Event event, String a, String b) =>
    event.player(a).avoid.contains(b) || event.player(b).avoid.contains(a);

void checkPairingRequests(Event event, Iterable<Game> games) {
  for (final game in games) {
    if (pairingRestricted(event, game.white, game.black)) {
      throw TournamentException(
        '${event.player(game.white).name} and ${event.player(game.black).name} have a do-not-pair request. Move them to different sections or remove the request in player details.',
      );
    }
  }
}

/// Names one game of round [round] from its colors. Within a round an ordered
/// pair is unique, so a derived ID never outlives the pairing it names.
typedef GameIdFor = String Function(int round, String white, String black);

/// Players unavailable in round [n] receive their bye award up front. Shared
/// by every format that pairs round by round or from a fixed table.
(List<String>, List<ByeAward>) roundAvailability(
  Event event,
  Section section,
  int n,
) {
  final byes = <ByeAward>[];
  final available = section.players.where((pid) {
    final p = event.player(pid);
    if (p.withdrawn) {
      byes.add(ByeAward(pid, 0, 'Withdrawn'));
      return false;
    }
    if (p.byes.containsKey(n)) {
      byes.add(ByeAward(pid, p.byes[n]!, 'Requested bye'));
      return false;
    }
    return true;
  }).toList();
  return (available, byes);
}

/// Round [n] of a fixed (quad or round-robin) schedule, refused exactly as
/// posting refuses it: an absence or a do-not-pair request cannot be skipped.
Round scheduledRound(Event event, Section section, int n, GameIdFor id) {
  final (available, byes) = roundAvailability(event, section, n);
  final schedule = sectionSchedule(section);
  if (n > schedule.length) {
    throw const TournamentException('The round-robin schedule is complete.');
  }
  // Catch an impossible fixed schedule before posting its first round,
  // including a requested avoidance whose meeting would be in a later round.
  for (final (offset, remaining) in schedule.skip(n - 1).indexed) {
    for (final (a, b) in remaining) {
      if (a != null && b != null && pairingRestricted(event, a, b)) {
        throw TournamentException(
          '${event.player(a).name} and ${event.player(b).name} have a do-not-pair request, but round ${n + offset} requires them to meet. A round robin cannot skip this meeting; move them to different sections or remove the request.',
        );
      }
    }
  }
  final pairs = <(String, String)>[];
  for (final (a, b) in schedule[n - 1]) {
    if (a == null || b == null) {
      final pid = a ?? b;
      if (pid != null && available.contains(pid)) {
        byes.add(ByeAward(pid, 0, 'Round-robin sit-out'));
      }
      continue;
    }
    if (available.contains(a) && available.contains(b)) {
      pairs.add((a, b));
    } else if (available.contains(a) || available.contains(b)) {
      final absent = byes.firstWhere(
        (bye) => bye.player == a || bye.player == b,
      );
      throw TournamentException(
        'Round $n pairs ${event.player(a).name} with ${event.player(b).name}, but ${event.player(absent.player).name} is unavailable (${absent.reason.toLowerCase()}). '
        'Make them available and record a forfeit if they do not play, or combine into Swiss.',
      );
    }
  }
  return _round(section, n, pairs, byes, id);
}

/// Round [n] of a fixed schedule as printed on paper: everyone listed, with
/// availability left to the TD at the board.
Round paperRound(Section section, int n) {
  final pairs = <(String, String)>[], byes = <ByeAward>[];
  for (final (a, b) in sectionSchedule(section)[n - 1]) {
    if (a != null && b != null) {
      pairs.add((a, b));
    } else if ((a ?? b) case final pid?) {
      byes.add(ByeAward(pid, 0, 'Round-robin sit-out'));
    }
  }
  return _round(
    section,
    n,
    pairs,
    byes,
    (round, white, black) => 'paper-${section.id}-$round-$white-$black',
  );
}

/// Whether [g], unresolved in round [round] of [section], may stand while
/// the next round is paired: it carries a pairing assumption, or it is an
/// adjourned game of a FIDE Swiss's latest round, which counts as a draw
/// for that one pairing (C.04.2 3.1).
bool pairsWithoutResult(Section section, int round, Game g) =>
    g.pairingAssumption != null ||
    (g.outcome == Outcome.unfinished &&
        section.fideRated &&
        pairingFormat(section) == Format.swiss &&
        round == section.rounds.length);

/// Whether every game of [section] has a result the next pairing can use.
bool readyToPair(Section section) => section.rounds.every(
  (r) => r.games.every(
    (g) => g.outcome.resolved || pairsWithoutResult(section, r.number, g),
  ),
);

/// The next round of [section]: a fixed schedule for quads and round robins,
/// otherwise US Chess Swiss pairings (rules 27–29) from `swiss_pairing.dart`.
Round proposeRound(Event event, Section section, String Function() id) {
  final n = section.rounds.length + 1;
  // A knockout's length follows its bracket (tie-break postings add
  // rounds), and it names unreported boards itself.
  if (pairingFormat(section) == Format.knockout) {
    return knockoutRound(event, section, n, id);
  }
  if (n > section.plannedRounds) {
    throw const TournamentException('All planned rounds have been posted.');
  }
  for (final r in section.rounds) {
    for (final g in r.games) {
      if (g.outcome.resolved || pairsWithoutResult(section, r.number, g)) {
        continue;
      }
      if (section.fideRated && g.outcome == Outcome.unfinished) {
        throw TournamentException(
          'Board ${g.board} of round ${r.number} is still adjourned. An adjourned game counts as a draw for one pairing only; enter its result before pairing round $n.',
        );
      }
      throw const TournamentException(
        'Resolve outstanding games or record a TD-approved temporary pairing treatment before posting.',
      );
    }
  }
  switch (pairingFormat(section)) {
    case Format.quad || Format.roundRobin:
      return scheduledRound(event, section, n, (_, _, _) => id());
    case Format.scheveningen:
      return scheveningenRound(event, section, n, id);
    case Format.knockout:
      throw StateError('Knockout is paired above.');
    case Format.ladder:
      throw const TournamentException(
        'A ladder has no rounds to create: record challenge games from the ladder.',
      );
    case Format.bughouse:
      return bughouseRound(event, section, n, id);
    case Format.swiss:
      break;
  }
  final (available, byes) = roundAvailability(event, section, n);
  final proposal = section.fideRated
      ? pairFideDutch(event, section, n, byes)
      : pairSwiss(event, section, n, available, byes);
  return _round(
    section,
    n,
    proposal.games,
    proposal.byes,
    (_, _, _) => id(),
    explanations: proposal.explanations,
    policy: section.fideRated ? fideDutchPolicy : null,
    fixedBoards: {
      for (final p in event.players)
        if (p.fixedBoard > 0) p.id: p.fixedBoard,
    },
  );
}

/// Rule 29G3 selective re-pairing: the latest round of a Swiss [section]
/// keeps the games in [keep] (those already started) and re-pairs everyone
/// else as a separate group by the normal methods, for instance after a
/// player withdrew once pairings were posted. The holder of the round's
/// full-point bye and any house player left out rejoin that group, so an
/// odd group settles the bye again. Kept games keep their IDs and boards;
/// the new games take the freed boards first.
Round repairUnstartedRound(
  Event event,
  Section section,
  Set<String> keep,
  String Function() id,
) {
  if (pairingFormat(section) != Format.swiss) {
    throw const TournamentException(
      'Selective re-pairing (29G3) applies to Swiss rounds.',
    );
  }
  if (section.fideRated) {
    throw const TournamentException(
      'Selective re-pairing is US Chess rule 29G3. In a FIDE section, unpair the round and pair it again, or change the waiting pairings by hand.',
    );
  }
  final round = section.rounds.lastOrNull;
  if (round == null) {
    throw const TournamentException('No round has been posted.');
  }
  final n = round.number;
  final known = round.games.map((g) => g.id).toSet();
  final unknown = keep.difference(known);
  if (unknown.isNotEmpty) {
    throw TournamentException(
      'Game ${unknown.first} is not in round $n. Choose the games to keep from the latest round.',
    );
  }
  // A double-game pairing is kept or re-paired as a whole.
  bool kept(Game g) => round.games.any(
    (k) =>
        keep.contains(k.id) &&
        {k.white, k.black}.containsAll([g.white, g.black]) &&
        k.board == g.board,
  );
  final redo = round.games.where((g) => !kept(g)).toList();
  if (redo.isEmpty) {
    throw const TournamentException(
      'Every game is kept: there is nothing to re-pair.',
    );
  }
  for (final g in redo) {
    if (g.outcome != Outcome.unreported || g.pairingAssumption != null) {
      throw TournamentException(
        'Board ${g.board} already has a result. Keep every game that has started (29G2) and re-pair only the waiting boards.',
      );
    }
  }
  final waiting = <String>{
    for (final g in redo) ...[g.white, g.black],
    for (final b in round.byes)
      if (b.allocated || b.reason == 'House player not needed') b.player,
  };
  final byes = <ByeAward>[
    for (final b in round.byes)
      if (!waiting.contains(b.player)) b,
  ];
  final available = <String>[];
  for (final pid in section.players.where(waiting.contains)) {
    final p = event.player(pid);
    if (p.withdrawn) {
      byes.add(ByeAward(pid, 0, 'Withdrawn'));
    } else if (p.byes.containsKey(n)) {
      byes.add(ByeAward(pid, p.byes[n]!, 'Requested bye'));
    } else {
      available.add(pid);
    }
  }
  // Pair from the history before this round.
  final before = section.copy(rounds: section.rounds.sublist(0, n - 1));
  final history = event.copy(
    sections: [for (final s in event.sections) s.id == section.id ? before : s],
  );
  final proposal = pairSwiss(history, before, n, available, byes);
  final keptGames = round.games.where(kept).toList();
  final taken = keptGames.map((g) => g.board).toSet();
  final freed = (redo.map((g) => g.board).toSet().toList()..sort());
  var next = section.boardStart;
  int board() {
    if (freed.isNotEmpty) return freed.removeAt(0);
    while (taken.contains(next)) {
      next++;
    }
    taken.add(next);
    return next++;
  }

  final games = [...keptGames];
  for (final (white, black) in proposal.games) {
    final b = board();
    taken.add(b);
    games.add(Game(id: id(), white: white, black: black, board: b));
    if (section.doubleGames) {
      games.add(Game(id: id(), white: black, black: white, board: b, leg: 2));
    }
  }
  games.sort(
    (a, b) => a.board != b.board
        ? a.board.compareTo(b.board)
        : a.leg.compareTo(b.leg),
  );
  return round.copy(
    games: games,
    byes: proposal.byes,
    revision: round.revision + 1,
    explanations: [
      'Selective re-pairing (29G3): ${keptGames.length} game${keptGames.length == 1 ? '' : 's'} kept; ${available.length} waiting player${available.length == 1 ? '' : 's'} re-paired as a separate group.',
      ...proposal.explanations,
    ],
  );
}

/// Boards follow [pairs] from the section's first board; a double-game pair
/// plays its second leg on the same board with colors reversed. A player
/// with a fixed board (rule 20M3 / 35) keeps it; the other games fill the
/// remaining boards in order.
Round _round(
  Section section,
  int n,
  List<(String, String)> pairs,
  List<ByeAward> byes,
  GameIdFor id, {
  List<String> explanations = const [],
  Map<String, int> fixedBoards = const {},
  String? policy,
}) {
  final format = pairingFormat(section);
  final colorLot = quadColorLot(section);
  final games = <Game>[];
  final boards = <int>[];
  final taken = <int>{};
  for (final (white, black) in pairs) {
    final fixed = fixedBoards[white] ?? fixedBoards[black];
    if (fixed != null && taken.add(fixed)) {
      boards.add(fixed);
    } else {
      boards.add(0);
    }
  }
  var nextBoard = section.boardStart;
  for (var i = 0; i < boards.length; i++) {
    if (boards[i] != 0) continue;
    while (taken.contains(nextBoard)) {
      nextBoard++;
    }
    boards[i] = nextBoard;
    taken.add(nextBoard++);
  }
  for (final (index, (white, black)) in pairs.indexed) {
    games.add(
      Game(
        id: id(n, white, black),
        white: white,
        black: black,
        board: boards[index],
      ),
    );
    if (section.doubleGames) {
      games.add(
        Game(
          id: id(n, black, white),
          white: black,
          black: white,
          board: boards[index],
          leg: 2,
        ),
      );
    }
  }
  games.sort(
    (a, b) => a.board != b.board
        ? a.board.compareTo(b.board)
        : a.leg.compareTo(b.leg),
  );
  return Round(
    number: n,
    games: games,
    byes: byes,
    explanations: explanations,
    note: format == Format.quad
        ? section.quadPairings.isNotEmpty
              ? 'Manual quad pairings.'
              : 'Recorded final-round color lot: $colorLot (derived from the randomly assigned section ID).'
        : '',
    policy:
        policy ??
        (format == Format.quad
            ? section.quadPairings.isNotEmpty
                  ? 'quad-manual-v1'
                  : 'quad-30G-seeded-v1'
            : format == Format.swiss
            ? swissPolicy
            : section.rrTable == crenshawTable
            ? 'crenshaw-rr-v1'
            : 'circle-rr-v1'),
  );
}

/// A quad's fixed schedule is available before any result is entered.
bool hasFixedQuadSchedule(Section s) =>
    s.format == Format.quad && s.players.length == 4 && !s.sideGames;

/// Posted rounds followed by the unposted rest of a fixed quad schedule, so a
/// result can be entered in any round without a posting step. Each projected
/// round passes the posting checks, and projection stops at the first round
/// posting would refuse; [QuadProjection.issue] says why.
typedef QuadProjection = ({List<Round> rounds, String? issue});

QuadProjection projectQuad(Event event, Section s) {
  if (!hasFixedQuadSchedule(s)) return (rounds: s.rounds, issue: null);
  final rounds = [...s.rounds];
  final last = min(s.plannedRounds, sectionSchedule(s).length);
  // Projected IDs derive from the pairing, so editing the schedule retires
  // them instead of pointing a stale ID at different players.
  String id(int round, String white, String black) =>
      'quad-${s.id}-$round-$white-$black';
  while (rounds.length < last) {
    try {
      rounds.add(
        scheduledRound(event, s.copy(rounds: rounds), rounds.length + 1, id),
      );
    } on TournamentException catch (e) {
      return (rounds: rounds, issue: e.message);
    }
  }
  return (rounds: rounds, issue: null);
}
