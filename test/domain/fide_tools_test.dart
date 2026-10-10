import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/fide_checker.dart';
import 'package:meow_chess/domain/fide_generator.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/standings.dart';
import 'package:meow_chess/domain/trf.dart';
import 'package:meow_chess/domain/trf_read.dart';

/// The random tournament generator and the pairings and tie-breaks
/// checker: what one writes, the other reads back without a difference.
void main() {
  const variants = {
    'plain': RandomTournamentSettings(players: 24, rounds: 7),
    'byes, forfeits, withdrawals, late entries': RandomTournamentSettings(
      players: 31,
      rounds: 9,
      forfeitRate: 0.06,
      halfByeRate: 0.08,
      zeroByeRate: 0.04,
      fullByeRate: 0.01,
      withdrawRate: 0.03,
      lateEntryRate: 0.1,
    ),
    'Baku acceleration': RandomTournamentSettings(
      players: 40,
      rounds: 9,
      baku: true,
    ),
    'bye scores a draw, unusual and short games': RandomTournamentSettings(
      players: 17,
      rounds: 6,
      pabPoints: 1,
      unusualRate: 0.05,
      shortGameRate: 0.05,
      tiebreaks: ['STD', 'BH/C1/P', 'SB/C2', 'PS/C2', 'TPN/R'],
    ),
    'rating tie-breaks': RandomTournamentSettings(
      players: 22,
      rounds: 7,
      tiebreaks: ['ARO/M1', 'TPR', 'PTP', 'APRO', 'APPO', 'RTNG/R'],
    ),
  };
  for (final MapEntry(key: name, value: settings) in variants.entries) {
    test('generated tournaments pass the checker: $name', () {
      for (var seed = 1; seed <= 4; seed++) {
        final s = RandomTournamentSettings(
          players: settings.players,
          rounds: settings.rounds,
          seed: seed,
          forfeitRate: settings.forfeitRate,
          halfByeRate: settings.halfByeRate,
          zeroByeRate: settings.zeroByeRate,
          fullByeRate: settings.fullByeRate,
          withdrawRate: settings.withdrawRate,
          lateEntryRate: settings.lateEntryRate,
          unusualRate: settings.unusualRate,
          shortGameRate: settings.shortGameRate,
          baku: settings.baku,
          pabPoints: settings.pabPoints,
          tiebreaks: settings.tiebreaks,
        );
        final e = generateFideTournament(s);
        final trf = writeTrf(e, e.sections.single);
        final report = checkTrf(trf);
        expect(report.issues, isEmpty, reason: '$name seed $seed\n$trf');
      }
    });
  }

  test('a TRF reads back as the same tournament', () {
    final e = generateFideTournament(
      const RandomTournamentSettings(
        players: 15,
        rounds: 5,
        seed: 7,
        pabPoints: 1,
        unusualRate: 0.1,
        shortGameRate: 0.1,
        halfByeRate: 0.1,
      ),
    );
    final s = e.sections.single;
    final trf = writeTrf(e, s);
    var n = 0;
    final back = trfToEvent(
      TrfFile.parse(trf),
      newId: () => 'i${n++}',
      today: '2026-10-10',
    ).event;
    final t = back.sections.single;
    expect(t.pabPoints, 1);
    expect(t.rounds.length, s.rounds.length);
    expect(writeTrf(back, t).split('\r\n').skip(1), trf.split('\r\n').skip(1));
    String rows(Event ev) => [
      for (final row in standings(ev, ev.sections.single))
        '${row.rank} ${row.points} ${row.tiebreaks.map((t) => t.value).join(',')}',
    ].join('\n');
    expect(rows(back), rows(e));
  });

  test('the checker reports a changed pairing and a wrong place', () {
    final e = generateFideTournament(
      const RandomTournamentSettings(players: 12, rounds: 5, seed: 3),
    );
    final trf = writeTrf(e, e.sections.single);
    final lines = trf.split('\r\n');
    // Swap the places of the first two players.
    final i = lines.indexWhere((l) => l.startsWith('001    1'));
    final j = lines.indexWhere((l) => l.startsWith('001    2'));
    String place(String l) => l.substring(85, 89);
    String withPlace(String l, String p) =>
        l.substring(0, 85) + p + l.substring(89);
    final a = place(lines[i]), b = place(lines[j]);
    lines[i] = withPlace(lines[i], b);
    lines[j] = withPlace(lines[j], a);
    final report = checkTrf(lines.join('\r\n'));
    expect(report.ok, a == b);
    expect(report.issues.every((x) => x.round == 0), isTrue);
  });

  test('the checker finds a pairing the engine would not make', () {
    final e = generateFideTournament(
      const RandomTournamentSettings(players: 14, rounds: 5, seed: 5),
    );
    final s = e.sections.single;
    // Round 3 with the black players of boards 1 and 2 exchanged (and
    // nobody meeting twice).
    final r3 = s.rounds[2];
    final g1 = r3.games[0], g2 = r3.games[1];
    final swapped = r3.copy(
      games: [
        g1.copy(black: g2.black),
        g2.copy(black: g1.black),
        ...r3.games.skip(2),
      ],
    );
    final changed = e.copy(
      sections: [
        s.copy(rounds: [...s.rounds.take(2), swapped, ...s.rounds.skip(3)]),
      ],
    );
    final report = checkTrf(
      writeTrf(changed, changed.sections.single),
      ranking: false,
    );
    expect(report.issues.map((i) => i.round), contains(3));
  });

  test('time controls convert from TRF record 222', () {
    expect(timeControlFromTrf('5400+30'), 'G/90 inc/30');
    expect(timeControlFromTrf('40/6000+30:900+30'), '40/100, SD/15 inc/30');
    expect(timeControlFromTrf('W300-B240'), isNull);
    expect(timeControlFromTrf('5430'), isNull);
  });

  test('tie-break codes read case-insensitively, GE as REP', () {
    expect(fideTiebreakCode('bh/c1'), 'BH/C1');
    expect(fideTiebreakCode('BH-C1'), 'BH/C1');
    expect(fideTiebreakCode('GE'), 'REP');
    expect(fideTiebreakCode('KS/L+2'), 'KS/L+2');
    expect(fideTiebreakCode('EMMSB'), isNull);
  });

  test('team files and other scoring systems are refused', () {
    expect(
      () => TrfFile.parse('012 Teams\r\n310   1 A\r\n'),
      throwsA(isA<TrfFormatException>()),
    );
    final f = TrfFile.parse(
      '162  W 3.0      D 1.0\r\n001    1      A, B                              1500                     0.0    1\r\n',
    );
    expect(
      () => trfToEvent(f, newId: () => 'x', today: '2026-10-10'),
      throwsA(isA<TrfFormatException>()),
    );
  });
}
