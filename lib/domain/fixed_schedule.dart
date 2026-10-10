import 'model.dart';

/// A quad that no longer has exactly four players before its first round
/// (after moves or late entries) pairs as a small Swiss instead.
Format pairingFormat(Section section) =>
    section.format == Format.quad &&
        section.rounds.isEmpty &&
        section.players.length != 4
    ? Format.swiss
    : section.format;

/// Quads and round robins play a schedule fixed before round 1; every other
/// format pairs round by round.
bool hasFixedSchedule(Section section) =>
    const [Format.quad, Format.roundRobin].contains(pairingFormat(section));

/// The same recorded color lot must be used on paper and when posting rounds.
int quadColorLot(Section section) =>
    section.id.codeUnits.fold<int>(0, (sum, c) => (sum * 31 + c) & 0x7fffffff) &
    3;

/// Rule 30A: the section's table policy. Empty is the circle method.
const crenshawTable = 'crenshaw';

/// The largest field the rulebook's Chapter 12 tables cover (23–24 players).
const crenshawMaxPlayers = 24;

/// Shared by posting, the editor and printable full schedules. A double
/// round robin (rule 30F, [Section.doubleCycle]) is the schedule followed by
/// a second cycle with every color reversed.
List<List<(String?, String?)>> sectionSchedule(Section section) {
  final List<List<(String?, String?)>> cycle;
  if (section.format == Format.quad &&
      section.players.length == 4 &&
      section.quadPairings.isNotEmpty) {
    cycle = [
      for (final r in section.quadPairings)
        [
          (section.players[r[0]], section.players[r[1]]),
          (section.players[r[2]], section.players[r[3]]),
        ],
    ];
  } else {
    cycle = roundRobinSchedule(
      section.players,
      quad: section.format == Format.quad,
      colorLot: quadColorLot(section),
      table: section.rrTable,
    );
  }
  if (!section.doubleCycle || !hasFixedSchedule(section)) return cycle;
  return [
    ...cycle,
    for (final round in cycle) [for (final (w, b) in round) (b, w)],
  ];
}

/// Rule 30F: why [section]'s planned rounds do not fit its double cycle, or
/// null. Each cycle plays everyone once, so the second cycle doubles the
/// round count; a shorter plan would never reverse every color.
String? doubleCycleProblem(Section section) {
  if (!section.doubleCycle ||
      !hasFixedSchedule(section) ||
      section.sideGames ||
      section.players.length < 2) {
    return null;
  }
  final length = sectionSchedule(section).length;
  if (section.plannedRounds == length) return null;
  final n = section.players.length;
  return 'A double round robin of $n players is $length rounds '
      '(two cycles of ${length ~/ 2}). Set the number of rounds to $length.';
}

List<List<(String?, String?)>> roundRobinSchedule(
  List<String> players, {
  bool quad = false,
  int colorLot = 0,
  String table = '',
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
  if (table == crenshawTable && players.length >= 3) {
    if (players.length > crenshawMaxPlayers) {
      throw TournamentException(
        'The Crenshaw-Berger tables cover 3 to $crenshawMaxPlayers players; '
        'this section has ${players.length}. Use the circle method.',
      );
    }
    // The highest number of an odd field is the sit-out, as in Chapter 12.
    String? player(int number) =>
        number <= players.length ? players[number - 1] : null;
    return [
      for (final round in crenshawPairings(players.length))
        [for (final (w, b) in round) (player(w), player(b))],
    ];
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

/// Rule 30A / Chapter 12: the Crenshaw-Berger table for a field of
/// [players] (3–24), as rounds of (white, black) pairing numbers. Numbers run
/// 1..n with n rounded up to even; an odd field's extra number is the
/// sit-out. The 3–4 table is the quad table printed under rule 30G. The 5–6
/// table follows its own rotation (its first round is the one rule 29L's TD
/// TIP reads from Table B). From 7–8 up, the printed tables are the Berger
/// tables with the rounds in reverse order, which is what the Crenshaw
/// revision changed so colors can still be adjusted after a withdrawal.
List<List<(int, int)>> crenshawPairings(int players) {
  if (players < 3 || players > crenshawMaxPlayers) {
    throw TournamentException(
      'The Crenshaw-Berger tables cover 3 to $crenshawMaxPlayers players.',
    );
  }
  final n = players.isOdd ? players + 1 : players;
  switch (n) {
    case 4:
      return const [
        [(1, 4), (2, 3)],
        [(3, 1), (4, 2)],
        [(1, 2), (3, 4)],
      ];
    case 6:
      return const [
        [(3, 6), (5, 4), (1, 2)],
        [(2, 6), (4, 1), (3, 5)],
        [(6, 5), (1, 3), (4, 2)],
        [(6, 4), (5, 1), (2, 3)],
        [(1, 6), (2, 5), (3, 4)],
      ];
  }
  final berger = _bergerTable(n);
  return berger.reversed.toList();
}

/// The Berger table for an even [n]: in round r the pivot (player n) meets
/// the head h, with white when r is even; every other board is h+k against
/// h-k around the circle of 1..n-1, the first with white.
List<List<(int, int)>> _bergerTable(int n) {
  int wrap(int x) => (x - 1) % (n - 1) + 1;
  return [
    for (var r = 1; r < n; r++)
      () {
        final h = r.isOdd ? (r + 1) ~/ 2 : r ~/ 2 + n ~/ 2;
        return [
          r.isOdd ? (h, n) : (n, h),
          for (var k = 1; k < n ~/ 2; k++) (wrap(h + k), wrap(h - k)),
        ];
      }(),
  ];
}
