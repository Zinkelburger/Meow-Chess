import 'model.dart';
import 'pairing.dart' show roundAvailability, pairingRestricted;

/// Scheveningen: two sides meet on a fixed table (every player of side A
/// plays every player of side B once), rounds = max(boards per side).
///
/// Side A is the section's players whose team label is [Section.homeTeam]
/// (case-insensitive, trimmed); side B is everyone else. Sides may differ
/// in size: the larger side sits a player out each round, rotated so every
/// player sits out equally often. Colors: in round r the pair (A[i], B[j])
/// gives White to A when i + j is even, so every player's colors are
/// balanced within one and alternate round by round (with one repeat at the
/// wrap of an odd table). On an even table that means side A has White on
/// every board in round 1, side B in round 2, and so on, as club team
/// matches are played.
const scheveningenPolicy = 'scheveningen-v1';

String _label(String team) => team.trim().toLowerCase();

/// Half-points as "5½", "3" or "½".
String _half(int halves) => halves == 1
    ? '½'
    : halves.isOdd
    ? '${halves ~/ 2}½'
    : '${halves ~/ 2}';

/// The two sides in roster order: (side A, side B).
(List<String>, List<String>) scheveningenSides(Event event, Section section) {
  final home = _label(section.homeTeam);
  final a = <String>[], b = <String>[];
  for (final id in section.players) {
    (_label(event.player(id).team) == home && home.isNotEmpty ? a : b).add(id);
  }
  return (a, b);
}

/// The label of side B: the one other team label when there is exactly one,
/// otherwise "the rest".
String scheveningenAwayLabel(Event event, Section section) {
  final (_, b) = scheveningenSides(event, section);
  final labels = {
    for (final id in b)
      if (event.player(id).team.trim().isNotEmpty) event.player(id).team.trim(),
  };
  return labels.length == 1 ? labels.single : 'the rest';
}

/// Why [section] cannot be played as a Scheveningen, or null.
String? scheveningenProblem(Event event, Section section) {
  if (section.homeTeam.trim().isEmpty) {
    return 'Give the players two team labels first, then choose the home team.';
  }
  final (a, b) = scheveningenSides(event, section);
  if (a.isEmpty) {
    return 'No player in this section is on team "${section.homeTeam.trim()}". Give the players two team labels first.';
  }
  if (b.isEmpty) {
    return 'Every player in this section is on team "${section.homeTeam.trim()}". Give the players two team labels first.';
  }
  return null;
}

/// The full table as rounds of (white, black); a null slot marks the
/// opponent's sit-out when the sides differ in size.
List<List<(String?, String?)>> scheveningenSchedule(
  Event event,
  Section section,
) {
  if (scheveningenProblem(event, section) case final problem?) {
    throw TournamentException(problem);
  }
  final (a, b) = scheveningenSides(event, section);
  final n = a.length > b.length ? a.length : b.length;
  String? home(int i) => i < a.length ? a[i] : null;
  String? away(int j) => j < b.length ? b[j] : null;
  return [
    for (var r = 0; r < n; r++)
      [
        for (var i = 0; i < n; i++)
          () {
            final j = (i + r) % n;
            final h = home(i), v = away(j);
            if (h == null && v == null) return null;
            return (i + j).isEven ? (h, v) : (v, h);
          }(),
      ].nonNulls.toList(),
  ];
}

/// Round [n] of the table, refused exactly as a round robin is: an absence
/// or a do-not-pair request cannot be skipped on a fixed table.
Round scheveningenRound(
  Event event,
  Section section,
  int n,
  String Function() id,
) {
  final schedule = scheveningenSchedule(event, section);
  if (n > schedule.length) {
    throw const TournamentException('The Scheveningen table is complete.');
  }
  final (available, byes) = roundAvailability(event, section, n);
  for (final (offset, remaining) in schedule.skip(n - 1).indexed) {
    for (final (a, b) in remaining) {
      if (a != null && b != null && pairingRestricted(event, a, b)) {
        throw TournamentException(
          '${event.player(a).name} and ${event.player(b).name} have a do-not-pair request, but round ${n + offset} requires them to meet. A Scheveningen cannot skip this meeting; move them to different sections or remove the request.',
        );
      }
    }
  }
  final pairs = <(String, String)>[];
  for (final (a, b) in schedule[n - 1]) {
    if (a == null || b == null) {
      final pid = a ?? b;
      if (pid != null && available.contains(pid)) {
        byes.add(ByeAward(pid, 0, 'Scheveningen sit-out'));
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
  final games = _games(section, pairs, id);
  final (aHalves, bHalves) = scheveningenScore(event, section);
  final home = section.homeTeam.trim(),
      away = scheveningenAwayLabel(event, section);
  return Round(
    number: n,
    games: games,
    byes: byes,
    policy: scheveningenPolicy,
    note: n == 1
        ? '$home vs $away: ${schedule.length} rounds, every player meets every opponent once.'
        : '$home ${_half(aHalves)} – $away ${_half(bHalves)} after round ${n - 1}.',
  );
}

/// Boards run from the section's first board; a double-game pair plays its
/// second leg on the same board with colors reversed.
List<Game> _games(
  Section section,
  List<(String, String)> pairs,
  String Function() id,
) {
  final games = <Game>[];
  var board = section.boardStart;
  for (final (white, black) in pairs) {
    games.add(Game(id: id(), white: white, black: black, board: board));
    if (section.doubleGames) {
      games.add(
        Game(id: id(), white: black, black: white, board: board, leg: 2),
      );
    }
    board++;
  }
  return games;
}

/// Round [n] of the table as printed on paper: everyone listed, with
/// availability left to the TD at the board (like `paperRound`).
Round scheveningenPaperRound(Event event, Section section, int n) {
  final pairs = <(String, String)>[], byes = <ByeAward>[];
  for (final (a, b) in scheveningenSchedule(event, section)[n - 1]) {
    if (a != null && b != null) {
      pairs.add((a, b));
    } else if ((a ?? b) case final pid?) {
      byes.add(ByeAward(pid, 0, 'Scheveningen sit-out'));
    }
  }
  var k = 0;
  return Round(
    number: n,
    games: _games(section, pairs, () => 'paper-${section.id}-$n-${k++}'),
    byes: byes,
    policy: scheveningenPolicy,
  );
}

/// The match score so far in half-points: (side A, side B). Only games
/// between the sides count; byes and sit-outs score nothing for the match.
(int, int) scheveningenScore(Event event, Section section) {
  final (a, _) = scheveningenSides(event, section);
  final home = a.toSet();
  var aHalves = 0, bHalves = 0;
  for (final game in section.rounds.expand((r) => r.games)) {
    if (!game.outcome.resolved) continue;
    final whiteHome = home.contains(game.white);
    if (whiteHome == home.contains(game.black)) continue;
    if (whiteHome) {
      aHalves += game.outcome.whiteScore;
      bHalves += game.outcome.blackScore;
    } else {
      bHalves += game.outcome.whiteScore;
      aHalves += game.outcome.blackScore;
    }
  }
  return (aHalves, bHalves);
}

/// "Lions 5½ – Tigers 2½" for the standings heading and the round note.
String scheveningenScoreLine(Event event, Section section) {
  final (aHalves, bHalves) = scheveningenScore(event, section);
  return '${section.homeTeam.trim()} ${_half(aHalves)} – '
      '${scheveningenAwayLabel(event, section)} ${_half(bHalves)}';
}
