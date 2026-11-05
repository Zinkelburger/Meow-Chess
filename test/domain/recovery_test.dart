import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/recovery.dart';

Event event({
  int players = 4,
  List<Section> sections = const [],
  List<Json> transitions = const [],
}) => Event(
  id: 'e',
  name: 'Club',
  date: '2026-11-05',
  players: [
    for (var i = 0; i < players; i++) Player(id: 'p$i', name: 'Player $i'),
  ],
  sections: sections,
  transitions: transitions,
);

Round round(int n, {Outcome outcome = Outcome.unreported}) => Round(
  number: n,
  games: [
    Game(id: 'g$n', white: 'p0', black: 'p1', board: 1, outcome: outcome),
  ],
);

Section section(
  String id,
  int rounds, {
  bool sideGames = false,
  Outcome outcome = Outcome.unreported,
  Format format = Format.swiss,
}) => Section(
  id: id,
  name: id == 'o'
      ? 'Open'
      : id == 'r'
      ? 'Reserve'
      : 'Side Games',
  players: const ['p0', 'p1'],
  format: format,
  plannedRounds: 4,
  sideGames: sideGames,
  rounds: [for (var n = 1; n <= rounds; n++) round(n, outcome: outcome)],
);

void main() {
  group('recoveryMarks', () {
    test('pairing a round marks the state before it', () {
      final marks = recoveryMarks(
        event(sections: [section('o', 2)]),
        event(sections: [section('o', 3)]),
      );
      expect(marks, hasLength(1));
      expect(marks.single.kind, RecoveryKind.pairing);
      expect(marks.single.title, 'Before round 3 pairings');
      expect(marks.single.detail, 'Open');
      expect(marks.single.round, 3);
      expect(marks.single.sectionIds, ['o']);
    });

    test('sections paired together share one mark per round', () {
      final marks = recoveryMarks(
        event(sections: [section('o', 0), section('r', 0)]),
        event(sections: [section('o', 1), section('r', 1)]),
      );
      expect(marks.single.detail, 'Open, Reserve');
      expect(marks.single.sectionIds, ['o', 'r']);
    });

    test('sections at different rounds get a mark each', () {
      final marks = recoveryMarks(
        event(sections: [section('o', 1), section('r', 0)]),
        event(sections: [section('o', 2), section('r', 1)]),
      );
      expect(marks.map((m) => m.title), [
        'Before round 2 pairings',
        'Before round 1 pairings',
      ]);
    });

    test('a new section posted at once counts from round 1', () {
      final marks = recoveryMarks(event(), event(sections: [section('o', 1)]));
      expect(marks.single.title, 'Before round 1 pairings');
    });

    test('unpairing marks the state before the removal', () {
      final marks = recoveryMarks(
        event(sections: [section('o', 4)]),
        event(sections: [section('o', 2)]),
      );
      expect(marks.single.kind, RecoveryKind.unpairing);
      expect(marks.single.title, 'Before unpairing round 3');
    });

    test('an import is a landmark and a single registration is not', () {
      expect(recoveryMarks(event(players: 4), event(players: 5)), isEmpty);
      final marks = recoveryMarks(event(players: 4), event(players: 28));
      expect(marks.single.title, 'Before importing 24 players');
      expect(marks.single.detail, '4 already registered');
      expect(
        recoveryMarks(event(players: 0), event(players: 3)).single.detail,
        'the roster was empty',
      );
      expect(marks.single.players, 24);
    });

    test('moving players names the destination', () {
      final marks = recoveryMarks(
        event(sections: [section('o', 1), section('r', 1)]),
        event(
          sections: [section('o', 1), section('r', 1)],
          transitions: [
            {
              'players': ['p0'],
              'target': 'r',
              'effectiveRound': 2,
            },
          ],
        ),
      );
      expect(marks.single.kind, RecoveryKind.transfer);
      expect(marks.single.detail, 'to Reserve');
    });

    test('side games and result entry are not landmarks', () {
      expect(
        recoveryMarks(
          event(sections: [section('s', 0, sideGames: true)]),
          event(sections: [section('s', 1, sideGames: true)]),
        ),
        isEmpty,
      );
      expect(
        recoveryMarks(
          event(sections: [section('o', 1)]),
          event(sections: [section('o', 1, outcome: Outcome.draw)]),
        ),
        isEmpty,
      );
    });
  });

  group('stateSummary', () {
    test('says how far each section has got', () {
      expect(
        stateSummary(
          event(
            sections: [
              section('o', 2),
              section('r', 1, outcome: Outcome.whiteWin),
              section('s', 1, sideGames: true),
            ],
          ),
        ),
        [
          'Open: round 2 of 4 paired, 0 of 1 result in',
          'Reserve: round 1 of 4 complete',
          '4 players registered',
        ],
      );
      expect(stateSummary(event(players: 1, sections: [section('o', 0)])), [
        'Open: not paired yet',
        '1 player registered',
      ]);
    });

    test('a knockout or ladder has no planned round count', () {
      expect(
        stateSummary(
          event(sections: [section('o', 2, format: Format.knockout)]),
        ).first,
        'Open: round 2 paired, 0 of 1 result in',
      );
    });
  });
}
