import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/team_standings.dart';

Section _section(Json extra) => Section.fromJson({
  'id': 's',
  'name': 'Open',
  'players': const <String>[],
  'format': 'knockout',
  'plannedRounds': 3,
  'boardStart': 1,
  'doubleGames': false,
  'rounds': const <Object>[],
  ...extra,
});

String _saved(Section s) => jsonEncode(s.toJson());

void main() {
  group('settings are read once and saved as they were read', () {
    test('unknown keys, key order and explicit defaults survive a save', () {
      final stored = {
        'byeRules': {'maxHalfByes': 0, 'lastHalfByeRound': 2, 'note': 'x'},
        'prizes': {
          'fundCents': 0,
          'basedOn': 10,
          'list': <Object>[],
          'extra': true,
        },
        'holland': {'role': 'prelim', 'group': 'g', 'qualifiers': 2},
        'bracket': {'tiebreak': 'blitz', 'gamesPerMatch': 2, 'custom': 1},
        'variations': ['29J', '29E4a'],
        'accelerated': 'sixths',
      };
      final s = _section(stored);
      final saved = s.toJson();
      for (final key in ['byeRules', 'prizes', 'holland', 'bracket']) {
        expect(jsonEncode(saved[key]), jsonEncode(stored[key]), reason: key);
      }
      expect(saved['variations'], ['29E4a', '29J']);
      expect(saved['accelerated'], 'sixths');
      expect(_saved(Section.fromJson(s.toJson())), _saved(s));
    });

    test('the typed values are what the stored ones say', () {
      final s = _section({
        'byeRules': {'lastHalfByeRound': 2, 'deadlineMinutes': 30},
        'holland': {'group': 'g', 'role': 'final', 'unbalanced': true},
        'bracket': {
          'gamesPerMatch': 1,
          'tiebreak': 'armageddon',
          'seeds': ['a', 'b'],
          'rounds': [
            {
              'stage': 1,
              'name': 'Final',
              'rounds': [1, 2],
              'decisions': [
                {'board': 1, 'advanced': 'a', 'reason': 'Coin'},
              ],
            },
          ],
        },
        'variations': ['28S5latest'],
        'accelerated': 'baku',
      });
      expect(s.byeRules.lastHalfByeRound, 2);
      expect(s.byeRules.deadlineMinutes, 30);
      expect(s.holland.role, HollandRole.finalStage);
      expect(s.holland.qualifiers, 1);
      expect(s.holland.unbalanced, isTrue);
      expect(s.bracket.gamesPerMatch, 1);
      expect(s.bracket.tiebreak, KnockoutTiebreak.armageddon);
      expect(s.bracket.seeds, ['a', 'b']);
      expect(s.bracket.problem, isNull);
      final round = s.bracket.rounds.single;
      expect((round.stage, round.name), (1, 'Final'));
      expect(round.rounds, [1, 2]);
      final d = round.decisions.single;
      expect((d.board, d.advanced, d.reason), (1, 'a', 'Coin'));
      expect(s.variations, {Variation.reentryLatestScore});
      expect(s.accelerated, Acceleration.baku);
    });

    test('an empty section stores none of them', () {
      final saved = Section(id: 's', name: 'Open', players: const []).toJson();
      for (final key in [
        'accelerated',
        'variations',
        'byeRules',
        'prizes',
        'holland',
        'bracket',
      ]) {
        expect(saved.containsKey(key), isFalse, reason: key);
      }
    });

    test('the color toss is read and saved by its stored code', () {
      final e = Event(id: 'e', name: 'E', date: '2026-01-01');
      expect(e.toJson().containsKey('colorToss'), isFalse);
      final tossed = Event.fromJson({
        ...e.toJson(),
        'colorToss': 'higherBlack',
      });
      expect(tossed.colorToss, ColorToss.higherBlack);
      expect(tossed.toJson()['colorToss'], 'higherBlack');
    });
  });

  group('stored values that cannot be used', () {
    test('an unknown acceleration, toss or variation is refused', () {
      expect(
        () => _section({'accelerated': 'quarters'}),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'message',
            'Invalid accelerated pairing method.',
          ),
        ),
      );
      expect(
        () => ColorToss.parse('lowerWhite'),
        throwsA(isA<TournamentException>()),
      );
      expect(
        () => _section({
          'variations': ['29Z'],
        }),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'message',
            startsWith('Unknown pairing variation "29Z"'),
          ),
        ),
      );
    });

    test('a bracket that cannot be used is kept, with the reason', () {
      final s = _section({
        'bracket': {'gamesPerMatch': 4, 'tiebreak': 'coin'},
      });
      expect(s.bracket.problem, contains('1 or 2'));
      expect(s.bracket.gamesPerMatch, 4);
      expect(s.bracket.tiebreak, KnockoutTiebreak.none);
      expect(s.toJson()['bracket'], {'gamesPerMatch': 4, 'tiebreak': 'coin'});
    });

    test('malformed team awards read as off for display only', () {
      final s = _section({
        'prizes': {
          'teams': {'method': 'coin'},
        },
      });
      expect(TeamAwards.tryOf(s), isNull);
      expect(() => TeamAwards.of(s), throwsA(isA<TournamentException>()));
      expect(s.prizes.hasTeamSetting, isTrue);
    });

    test('a malformed prize table is refused when the event is read', () {
      expect(
        () => _section({
          'prizes': {
            'list': [
              {'kind': 'place'},
            ],
          },
        }),
        throwsA(isA<TournamentException>()),
      );
    });
  });

  group('changes keep what they do not touch', () {
    test('new seeds and rounds go where they always went', () {
      final b = Bracket.fromJson({'tiebreak': 'rapid', 'x': 1});
      final seeded = b.withSeeds(['a', 'b']);
      expect(
        jsonEncode(seeded.toJson()),
        '{"tiebreak":"rapid","x":1,"seeds":["a","b"]}',
      );
      final played = seeded.withRounds([
        BracketRound(stage: 1, name: 'Final', rounds: [1]),
      ]);
      expect(
        jsonEncode(played.toJson()),
        '{"tiebreak":"rapid","x":1,"seeds":["a","b"],'
        '"rounds":[{"stage":1,"name":"Final","rounds":[1],"decisions":[]}]}',
      );
      expect(
        jsonEncode(played.rulesOnly.toJson()),
        '{"tiebreak":"rapid","x":1}',
      );
    });

    test('a new decision keeps the round record and the others as stored', () {
      final round = BracketRound.fromJson({
        'name': 'Final',
        'stage': 1,
        'decisions': [
          {'board': 2, 'advanced': 'c', 'reason': 'Coin', 'by': 'TD'},
        ],
        'rounds': [1],
      });
      final next = round.withDecisions([
        ...round.decisions,
        BracketDecision(board: 1, advanced: 'a', reason: 'Lots'),
      ]);
      expect(
        jsonEncode(next.toJson()),
        '{"name":"Final","stage":1,"decisions":['
        '{"board":2,"advanced":"c","reason":"Coin","by":"TD"},'
        '{"board":1,"advanced":"a","reason":"Lots"}],"rounds":[1]}',
      );
    });

    test('settings built in code are stored in the established order', () {
      expect(
        jsonEncode(
          const ByePolicy(maxHalfByes: 1, lastHalfByeRound: 3).toJson(),
        ),
        '{"lastHalfByeRound":3,"maxHalfByes":1}',
      );
      expect(
        jsonEncode(
          const Holland(group: 'g', role: HollandRole.prelim).toJson(),
        ),
        '{"group":"g","role":"prelim","qualifiers":1,"unbalanced":false}',
      );
      expect(const Holland().toJson(), isEmpty);
    });
  });
}
