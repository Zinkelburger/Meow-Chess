import 'dart:math';

import 'fixed_schedule.dart';
import 'model.dart';
import 'swiss_pairing.dart';

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

/// Quad seeding order: rating high to low, then name, then id.
int quadOrder(Player a, Player b) {
  final c = b.rating.compareTo(a.rating);
  if (c != 0) return c;
  final n = a.name.compareTo(b.name);
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

/// Players unavailable in round [n] receive their bye award up front.
(List<String>, List<ByeAward>) _availability(
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
  final (available, byes) = _availability(event, section, n);
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

/// The next round of [section]: a fixed schedule for quads and round robins,
/// otherwise US Chess Swiss pairings (rules 27–29) from `swiss_pairing.dart`.
Round proposeRound(Event event, Section section, String Function() id) {
  final n = section.rounds.length + 1;
  if (n > section.plannedRounds) {
    throw const TournamentException('All planned rounds have been posted.');
  }
  if (section.rounds
      .expand((r) => r.games)
      .any((g) => !g.outcome.resolved && g.pairingAssumption == null)) {
    throw const TournamentException(
      'Resolve outstanding games or record a TD-approved temporary pairing treatment before posting.',
    );
  }
  if (pairingFormat(section) != Format.swiss) {
    return scheduledRound(event, section, n, (_, _, _) => id());
  }
  final (available, byes) = _availability(event, section, n);
  final proposal = pairSwiss(event, section, n, available, byes);
  return _round(
    section,
    n,
    proposal.games,
    proposal.byes,
    (_, _, _) => id(),
    explanations: proposal.explanations,
    fixedBoards: {
      for (final p in event.players)
        if (p.fixedBoard > 0) p.id: p.fixedBoard,
    },
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
    policy: format == Format.quad
        ? section.quadPairings.isNotEmpty
              ? 'quad-manual-v1'
              : 'quad-30G-seeded-v1'
        : format == Format.swiss
        ? swissPolicy
        : section.rrTable == crenshawTable
        ? 'crenshaw-rr-v1'
        : 'circle-rr-v1',
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
