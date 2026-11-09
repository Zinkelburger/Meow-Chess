// Fixed events for the printed-sheet checks: nothing here is random, so the
// same PDF comes out on every run and every OS. See docs/TESTING.md.
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';

const _names = [
  'Alexandra Montgomery',
  'Benjamin Chen',
  'Zoë Ångström',
  'Daniel Kim',
  'Eleanor Thompson',
  'Felix Nguyen',
  'Gabriela Silva',
  'Henry Patel',
];

List<Player> _players(int count) => [
  for (var i = 0; i < count; i++)
    Player(
      id: 'p$i',
      name: i < _names.length ? _names[i] : 'Entrant ${i + 1} Lastname',
      rating: i % 9 == 8 ? 0 : 2100 - i * 23,
      memberId: '${12000000 + i}',
    ),
];

Event _event(String name, List<Player> players, Section section) => Event(
  id: name.toLowerCase().replaceAll(' ', '-'),
  name: name,
  date: '2026-11-14',
  revision: 7,
  players: players,
  sections: [section],
);

Round _played(Round round) {
  const outcomes = [Outcome.whiteWin, Outcome.draw, Outcome.blackWin];
  return round.copy(
    games: [
      for (final (i, g) in round.games.indexed)
        g.copy(outcome: outcomes[(i + round.number) % outcomes.length]),
    ],
  );
}

/// A quad with its first round played.
Event printQuad() {
  final players = _players(4);
  final section = Section(
    id: 'quad-a',
    name: 'Quad A',
    format: Format.quad,
    players: [for (final p in players) p.id],
  );
  return _event(
    'Saturday Quads',
    players,
    section.copy(rounds: [_played(paperRound(section, 1))]),
  );
}

/// A round robin of [count] with its first [played] rounds played.
Event printRoundRobin({int count = 8, int played = 2}) {
  final players = _players(count);
  final section = Section(
    id: 'closed',
    name: 'Closed',
    format: Format.roundRobin,
    plannedRounds: count.isEven ? count - 1 : count,
    players: [for (final p in players) p.id],
  );
  return _event(
    'Club Championship',
    players,
    section.copy(
      rounds: [
        for (var n = 1; n <= played; n++) _played(paperRound(section, n)),
      ],
    ),
  );
}

/// A Swiss of [count] with [played] of its five rounds paired; every round
/// but the last has results, as on the day when its sheet is printed.
Event printSwiss({int count = 60, int played = 3}) {
  final players = _players(count);
  final half = count ~/ 2;
  Round round(int n) => Round(
    number: n,
    games: [
      for (var i = 0; i < half; i++)
        Game(
          id: 'r$n-b${i + 1}',
          white: (i + n).isEven ? 'p$i' : 'p${half + (i + n - 1) % half}',
          black: (i + n).isEven ? 'p${half + (i + n - 1) % half}' : 'p$i',
          board: i + 1,
        ),
    ],
  );
  return _event(
    'Open Swiss',
    players,
    Section(
      id: 'open',
      name: 'Open',
      plannedRounds: 5,
      players: [for (final p in players) p.id],
      rounds: [
        for (var n = 1; n <= played; n++)
          n < played ? _played(round(n)) : round(n),
      ],
    ),
  );
}
