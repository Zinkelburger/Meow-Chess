import 'model.dart';

/// A quad that no longer has exactly four players before its first round
/// (after moves or late entries) pairs as a small Swiss instead.
Format pairingFormat(Section section) =>
    section.format == Format.quad &&
        section.rounds.isEmpty &&
        section.players.length != 4
    ? Format.swiss
    : section.format;

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
