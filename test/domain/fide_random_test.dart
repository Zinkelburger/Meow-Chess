import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/domain/trf.dart';

/// Random FIDE Swiss events paired round by round through the app's own
/// path, with forfeits, draws and requested byes. Each must pair to the end
/// with no repeated game and at most one pairing-allocated bye per player.
///
/// With `MEOW_TRF_DUMP=dir`, each finished event is also written as TRF so
/// BBP Pairings' checker can replay it (`bbpPairings --dutch f.trf -c`),
/// confirming the TRF Meow writes is what the engine paired from.
void main() {
  final dir = Platform.environment['MEOW_TRF_DUMP'];
  test('random FIDE Swiss events pair to the end', () {
    for (var seed = 0; seed < 40; seed++) {
      final rng = Random(seed);
      final n = 12 + rng.nextInt(30);
      final rounds = 5 + rng.nextInt(5);
      final players = [
        for (var i = 0; i < n; i++)
          Player(
            id: 'p$i',
            name: 'F$i L$i',
            rating: 1200 + rng.nextInt(1200),
            fideId: '${100000 + i}',
            fideStandard: rng.nextInt(5) == 0 ? 0 : 1400 + rng.nextInt(1000),
            byes: {if (rng.nextInt(8) == 0) 2 + rng.nextInt(3): 1},
          ),
      ];
      var e = Event(
        id: 'e$seed',
        name: 'Seed $seed',
        date: '2026-10-10',
        players: players,
        sections: [
          Section(
            id: 's',
            name: 'Open',
            players: [for (final p in players) p.id],
            plannedRounds: rounds,
            fideRated: true,
          ),
        ],
      );
      var ids = 0;
      for (var r = 1; r <= rounds; r++) {
        final s = e.sections.single;
        final round = proposeRound(e, s, () => 'g${ids++}');
        final played = round.copy(
          games: [
            for (final g in round.games)
              g.copy(
                outcome: switch (rng.nextInt(20)) {
                  0 => Outcome.whiteForfeit,
                  1 => Outcome.blackForfeit,
                  < 8 => Outcome.draw,
                  < 14 => Outcome.whiteWin,
                  _ => Outcome.blackWin,
                },
              ),
          ],
        );
        e = e.copy(
          sections: [
            s.copy(rounds: [...s.rounds, played]),
          ],
        );
      }
      final met = <String>{}, pab = <String>{};
      for (final r in e.sections.single.rounds) {
        // C.04.1: a forfeited game was not played; they may meet again.
        for (final g in r.games.where((g) => g.outcome.played)) {
          expect(met.add(([g.white, g.black]..sort()).join()), isTrue);
        }
        for (final b in r.byes.where((b) => b.allocated)) {
          expect(pab.add(b.player), isTrue, reason: 'seed $seed');
        }
      }
      if (dir != null) {
        File(
          '$dir/seed$seed.trf',
        ).writeAsStringSync(writeTrf(e, e.sections.single));
      }
    }
  });
}
