import 'dart:math';

import 'model.dart';
import 'standings.dart';

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

List<Section> makeQuads(Event e, String Function() id) {
  if (e.sections.any((s) => s.rounds.isNotEmpty)) {
    throw const TournamentException(
      'Rounds are already posted. Move or combine entries with an explicit transition instead.',
    );
  }
  final pool = e.players.where((p) => !p.withdrawn).toList()
    ..sort((a, b) {
      final c = b.rating.compareTo(a.rating);
      return c != 0
          ? c
          : a.name.compareTo(b.name) != 0
          ? a.name.compareTo(b.name)
          : a.id.compareTo(b.id);
    });
  final sizes = quadGroupSizes(pool.length);
  var offset = 0, board = 1;
  return sizes.indexed.map((item) {
    final (i, size) = item;
    final group = pool.skip(offset).take(size).map((p) => p.id).toList();
    offset += size;
    final section = Section(
      id: id(),
      name: size == 4 ? 'Quad ${i + 1}' : 'Bottom Swiss',
      players: group,
      format: size == 4 ? Format.quad : Format.swiss,
      boardStart: board,
    );
    board += (size + 1) ~/ 2;
    return section;
  }).toList();
}

/// A quad that no longer has exactly four players before its first round
/// (after moves or late entries) pairs as a small Swiss instead.
Format pairingFormat(Section section) =>
    section.format == Format.quad &&
        section.rounds.isEmpty &&
        section.players.length != 4
    ? Format.swiss
    : section.format;

/// Explicit player requests are independent of team membership.
bool pairingRestricted(Event event, String a, String b) =>
    event.player(a).avoid.contains(b) || event.player(b).avoid.contains(a);

/// The same recorded color lot must be used on paper and when posting rounds.
int quadColorLot(Section section) =>
    section.id.codeUnits.fold<int>(0, (sum, c) => (sum * 31 + c) & 0x7fffffff) &
    3;

/// Shared by posting, the editor and printable full schedules.
List<List<(String?, String?)>> sectionSchedule(Section section) {
  if (section.format == Format.quad &&
      section.players.length == 4 &&
      section.quadPairings.isNotEmpty) {
    return [
      for (final r in section.quadPairings)
        [
          (section.players[r[0]], section.players[r[1]]),
          (section.players[r[2]], section.players[r[3]]),
        ],
    ];
  }
  return roundRobinSchedule(
    section.players,
    quad: section.format == Format.quad,
    colorLot: quadColorLot(section),
  );
}

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

/// Bounded, deterministic score-group Swiss for pilot use. This is deliberately
/// not advertised as a certified US Chess rules implementation.
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
  final table = standings(event, section, forPairing: true);
  final scores = {for (final r in table) r.player.id: r.points};
  available.sort((a, b) {
    final score = scores[b]!.compareTo(scores[a]!);
    if (score != 0) return score;
    final rating = event.player(b).rating.compareTo(event.player(a).rating);
    return rating != 0 ? rating : a.compareTo(b);
  });
  final hadBye = event.sections
      .expand((s) => s.rounds)
      .expand((r) => r.byes)
      .where((b) => b.allocated)
      .map((b) => b.player)
      .toSet();
  final opponents = <String, Set<String>>{};
  // Balance is white minus black games; last is +1/-1 for the most recent color.
  final colors = <String, int>{}, last = <String, (int, int)>{};
  for (final s in event.sections) {
    for (final r in s.rounds) {
      for (final g in r.games) {
        if (!g.outcome.played && g.pairingAssumption == null) continue;
        opponents.putIfAbsent(g.white, () => {}).add(g.black);
        opponents.putIfAbsent(g.black, () => {}).add(g.white);
        colors[g.white] = (colors[g.white] ?? 0) + 1;
        colors[g.black] = (colors[g.black] ?? 0) - 1;
        for (final (pid, color) in [(g.white, 1), (g.black, -1)]) {
          if ((last[pid]?.$1 ?? 0) <= r.number) last[pid] = (r.number, color);
        }
      }
    }
  }
  // Equalize first, then alternate; round parity only breaks a complete tie.
  bool firstTakesWhite(String a, String b) {
    final balance = (colors[a] ?? 0).compareTo(colors[b] ?? 0);
    if (balance != 0) return balance < 0;
    final alternation = (last[a]?.$2 ?? 0).compareTo(last[b]?.$2 ?? 0);
    if (alternation != 0) return alternation < 0;
    return n.isOdd;
  }

  var nodes = 0;
  List<(String, String)>? match(List<String> left) {
    if (left.isEmpty) return [];
    if (++nodes > 100000) {
      throw const TournamentException(
        'Pairing search limit reached. Use a reviewed manual pairing or adjust the field.',
      );
    }
    final a = left.first;
    final choices = left
        .skip(1)
        .where(
          (b) =>
              !(opponents[a]?.contains(b) ?? false) &&
              !pairingRestricted(event, a, b),
        )
        .toList();
    choices.sort((b, c) {
      final distanceB = (scores[a]! - scores[b]!).abs(),
          distanceC = (scores[a]! - scores[c]!).abs();
      if (distanceB != distanceC) return distanceB.compareTo(distanceC);
      final target = left.length ~/ 2;
      return (left.indexOf(b) - target).abs().compareTo(
        (left.indexOf(c) - target).abs(),
      );
    });
    for (final b in choices) {
      final rest = match(left.where((x) => x != a && x != b).toList());
      if (rest != null) {
        final aWhite = firstTakesWhite(a, b);
        return [(aWhite ? a : b, aWhite ? b : a), ...rest];
      }
    }
    return null;
  }

  List<(String, String)>? result;
  if (available.length.isOdd) {
    for (final candidate in available.reversed.where(
      (p) => !hadBye.contains(p),
    )) {
      result = match(available.where((p) => p != candidate).toList());
      if (result != null) {
        byes.add(
          ByeAward(
            candidate,
            section.doubleGames ? 4 : 2,
            'Lowest eligible score with no prior allocated bye; feasible non-repeat pairing',
            allocated: true,
          ),
        );
        break;
      }
    }
  } else {
    result = match(available);
  }
  if (result == null) {
    throw const TournamentException(
      'No non-repeat pairing satisfies the opponent requests and bye limits. Review player requests or adjust the sections.',
    );
  }
  return _round(section, n, result, byes, (_, _, _) => id());
}

/// Boards follow [pairs] from the section's first board; a double-game pair
/// plays its second leg on the same board with colors reversed.
Round _round(
  Section section,
  int n,
  List<(String, String)> pairs,
  List<ByeAward> byes,
  GameIdFor id,
) {
  final format = pairingFormat(section);
  final colorLot = quadColorLot(section);
  final games = <Game>[];
  for (final (index, (white, black)) in pairs.indexed) {
    games.add(
      Game(
        id: id(n, white, black),
        white: white,
        black: black,
        board: section.boardStart + index,
      ),
    );
    if (section.doubleGames) {
      games.add(
        Game(
          id: id(n, black, white),
          white: black,
          black: white,
          board: section.boardStart + index,
          leg: 2,
        ),
      );
    }
  }
  return Round(
    number: n,
    games: games,
    byes: byes,
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
        ? 'score-swiss-pilot-v1'
        : 'circle-rr-v1',
  );
}

List<List<(String?, String?)>> roundRobinSchedule(
  List<String> players, {
  bool quad = false,
  int colorLot = 0,
}) {
  if (quad) {
    if (players.length != 4) {
      throw const TournamentException('A quad needs exactly four players.');
    }
    final p = players;
    return [
      [(p[0], p[3]), (p[1], p[2])],
      [(p[2], p[0]), (p[3], p[1])],
      [
        colorLot & 1 == 0 ? (p[0], p[1]) : (p[1], p[0]),
        colorLot & 2 == 0 ? (p[2], p[3]) : (p[3], p[2]),
      ],
    ];
  }
  if (players.length < 2) {
    throw const TournamentException(
      'A round robin needs at least two players.',
    );
  }
  // Keep the sit-out fixed for odd fields, so every real player rotates
  // through equal numbers of White and Black slots.
  final ring = <String?>[if (players.length.isOdd) null, ...players];
  final rounds = <List<(String?, String?)>>[];
  for (var r = 0; r < ring.length - 1; r++) {
    rounds.add([
      for (var i = 0; i < ring.length ~/ 2; i++)
        (i == 0 ? r.isEven : i.isEven)
            ? (ring[i], ring[ring.length - 1 - i])
            : (ring[ring.length - 1 - i], ring[i]),
    ]);
    ring.insert(1, ring.removeLast());
  }
  return rounds;
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
