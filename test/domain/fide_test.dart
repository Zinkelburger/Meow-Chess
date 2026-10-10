import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/fide.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/trf.dart';
import 'package:meow_chess/domain/us_chess.dart';

Event _event(int count, {bool dual = true, int rounds = 5}) {
  final players = [
    for (var i = 0; i < count; i++)
      Player(
        id: 'p$i',
        name: 'First$i Last$i',
        rating: 2100 - i * 40,
        memberId: '${12000000 + i}',
        fideId: '${200000 + i}',
        fideStandard: i == count - 1 ? 0 : 2000 - i * 37,
        federation: 'USA',
        sex: i.isEven ? 'm' : 'w',
        birthDate: '199$i',
        title: i == 0 ? 'FM' : '',
      ),
  ];
  return Event(
    id: 'fide-event',
    name: 'Fall Open',
    date: '2026-10-10',
    endDate: '2026-10-11',
    city: 'Boston',
    timeControl: 'G/90 inc/30',
    players: players,
    fide: const FideRegistration(
      chiefArbiter: FideOfficial(name: 'Ada Arbiter', id: '2000001'),
    ),
    sections: [
      Section(
        id: 's1',
        name: 'Open',
        players: [for (final p in players) p.id],
        plannedRounds: rounds,
        fideRated: true,
        unrated: !dual,
      ),
    ],
  );
}

/// Pairs and plays every round: the higher pairing number wins, every
/// third board is drawn.
Event _play(Event e) {
  var event = e;
  var gameIds = 0;
  for (var n = 1; n <= event.sections.single.plannedRounds; n++) {
    final s = event.sections.single;
    final round = proposeRound(event, s, () => 'g${gameIds++}');
    final played = round.copy(
      games: [
        for (final (i, g) in round.games.indexed)
          g.copy(
            outcome: i % 3 == 2
                ? Outcome.draw
                : g.white.compareTo(g.black) < 0
                ? Outcome.whiteWin
                : Outcome.blackWin,
          ),
      ],
    );
    event = event.copy(
      sections: [
        s.copy(rounds: [...s.rounds, played]),
      ],
    );
  }
  return event;
}

void main() {
  test('FIDE categories follow time for 60 moves', () {
    FideCategory? cat(String tc) => fideCategory(TimeControl.parse(tc));
    expect(cat('G/90 inc/30'), FideCategory.standard);
    expect(cat('G/60'), FideCategory.standard);
    expect(cat('G/45 d5'), FideCategory.rapid);
    expect(cat('G/10'), FideCategory.blitz);
    expect(cat('G/3 inc/2'), FideCategory.blitz);
    expect(cat('G/3'), isNull);
  });

  test('initial ranking is rating, then title, then name', () {
    final e = _event(3);
    final s = e.sections.single;
    final a = e.players[1].copy(fideStandard: 1900, title: '');
    final b = e.players[2].copy(fideStandard: 1900, title: 'WFM');
    expect(compareFideRanking(e, s, a, b), greaterThan(0));
  });

  test('FIDE Dutch pairs a full Swiss without repeats', () {
    final e = _play(_event(11));
    final s = e.sections.single;
    expect(s.rounds, hasLength(5));
    final met = <String>{};
    final pab = <String>[];
    for (final r in s.rounds) {
      expect(r.policy, 'fide-dutch-2026-bbp-6');
      final seen = <String>{};
      for (final g in r.games) {
        expect(seen.add(g.white) && seen.add(g.black), isTrue);
        expect(met.add(([g.white, g.black]..sort()).join()), isTrue);
      }
      final byes = r.byes.where((b) => b.allocated).toList();
      expect(byes, hasLength(1));
      pab.add(byes.single.player);
      expect(seen.length + 1, 11);
    }
    expect(pab.toSet(), hasLength(5), reason: 'C.04.3: one PAB per player');
  });

  test('round 1 follows C.04.3: top half meets bottom half', () {
    final e = _event(8);
    final r = proposeRound(e, e.sections.single, () => 'x');
    String key(String a, String b) => ([a, b]..sort()).join('-');
    final pairs = [for (final g in r.games) key(g.white, g.black)];
    final ranked = trfTournament(e, e.sections.single).players;
    for (var i = 0; i < 4; i++) {
      expect(pairs, contains(key(ranked[i].id, ranked[i + 4].id)));
    }
  });

  test('requested byes and withdrawals are not paired', () {
    var e = _event(8);
    e = e.copy(
      players: [
        for (final p in e.players)
          p.id == 'p3'
              ? p.copy(byes: {1: 1})
              : p.id == 'p5'
              ? p.copy(withdrawn: true)
              : p,
      ],
    );
    final r = proposeRound(e, e.sections.single, () => 'x');
    final paired = {
      for (final g in r.games) ...[g.white, g.black],
    };
    expect(paired, isNot(contains('p3')));
    expect(paired, isNot(contains('p5')));
    expect(r.byes.where((b) => b.allocated), isEmpty, reason: '6 paired');
  });

  test('TRF26 report keeps the fixed columns', () {
    final e = _play(_event(5, rounds: 3));
    final text = writeTrf(e, e.sections.single);
    expect(text.contains('\r\n'), isTrue);
    final lines = text.split('\r\n');
    expect(lines.first, startsWith('012 Fall Open – Open'));
    expect(lines, contains('102 Ada Arbiter (2000001)'));
    expect(lines, contains('172 USA FIDON'));
    final p1 = lines.firstWhere((l) => l.startsWith('001    1'));
    expect(p1.substring(9, 10), 'm');
    expect(p1.substring(10, 13), ' FM');
    expect(p1.substring(14, 47).trim(), 'Last0, First0');
    expect(p1.substring(48, 52), '2000');
    expect(p1.substring(53, 56), 'USA');
    expect(p1.substring(57, 68).trim(), '200000');
    expect(p1.substring(69, 79), '1990/00/00');
    // Every round block: opponent (4), colour, result.
    for (var r = 0; r < 3; r++) {
      final block = p1.substring(91 + 10 * r, 91 + 10 * r + 8);
      expect(
        RegExp(r'^[ \d]{3}\d [wb-] [10=+\-HFUZ]$').hasMatch(block),
        isTrue,
        reason: block,
      );
    }
    final usa = lines.where((l) => l.startsWith('USA ')).toList();
    expect(usa, hasLength(5));
    expect(usa.first.substring(57, 68).trim(), '12000000');
  });

  test('FIDE-only sections rank by FIDE only and carry no NRS records', () {
    final e = _event(4, dual: false);
    final text = writeTrf(e, e.sections.single);
    expect(text, isNot(contains('172 ')));
    expect(text.split('\r\n').where((l) => l.startsWith('USA ')), isEmpty);
    expect(RatedBy.of(e.sections.single), RatedBy.fide);
  });

  test('round dates are the local day the round was played', () {
    // 8 pm local on 10 October, stored in UTC.
    final evening = DateTime(2026, 10, 10, 20).toUtc().toIso8601String();
    final e = _event(4, rounds: 1);
    final s = e.sections.single;
    final r = proposeRound(e, s, () => 'g').copy(postedAt: evening);
    final text = writeTrf(
      e,
      e
          .copy(
            sections: [
              s.copy(rounds: [r]),
            ],
          )
          .sections
          .single,
    );
    final dates = text.split('\r\n').firstWhere((l) => l.startsWith('132'));
    expect(dates.substring(91, 99), '26/10/10');
  });

  test('US Chess titles map to FIDE titles', () {
    expect(fideTitleFromCode('G'), 'GM');
    expect(fideTitleFromCode('WI'), 'WIM');
    expect(fideTitleFromCode(''), '');
  });
}
