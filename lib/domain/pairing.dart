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

/// Bounded, deterministic score-group Swiss for pilot use. This is deliberately
/// not advertised as a certified US Chess rules implementation.
Round proposeRound(Event event, Section section, String Function() id) {
  final n = section.rounds.length + 1;
  final colorLot =
      section.id.codeUnits.fold<int>(
        0,
        (sum, c) => (sum * 31 + c) & 0x7fffffff,
      ) &
      3;
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
  final pairs = <(String, String)>[];
  final format = pairingFormat(section);
  if (format != Format.swiss) {
    final schedule = roundRobinSchedule(
      section.players,
      quad: format == Format.quad,
      colorLot: colorLot,
    );
    if (n > schedule.length) {
      throw const TournamentException('The round-robin schedule is complete.');
    }
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
  } else {
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
          .where((b) => !(opponents[a]?.contains(b) ?? false))
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
              2,
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
        'No non-repeat pairing without a repeated full-point bye. Review the field or enter a manual round with an exception reason.',
      );
    }
    pairs.addAll(result);
  }
  final games = <Game>[];
  for (final (index, pair) in pairs.indexed) {
    games.add(
      Game(
        id: id(),
        white: pair.$1,
        black: pair.$2,
        board: section.boardStart + index,
      ),
    );
    if (section.doubleGames) {
      games.add(
        Game(
          id: id(),
          white: pair.$2,
          black: pair.$1,
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
        ? 'Recorded final-round color lot: $colorLot (derived from the randomly assigned section ID).'
        : '',
    policy: format == Format.quad
        ? 'quad-30G-seeded-v1'
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
  final ring = <String?>[...players, if (players.length.isOdd) null];
  final rounds = <List<(String?, String?)>>[];
  for (var r = 0; r < ring.length - 1; r++) {
    rounds.add([
      for (var i = 0; i < ring.length ~/ 2; i++)
        (r + i).isEven
            ? (ring[i], ring[ring.length - 1 - i])
            : (ring[ring.length - 1 - i], ring[i]),
    ]);
    ring.insert(1, ring.removeLast());
  }
  return rounds;
}
