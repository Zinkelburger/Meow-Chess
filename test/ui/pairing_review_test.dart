// PairingReview recognises the Swiss engine's decisions by a fragment of
// its wording. Each kind is provoked here from a real pairing, so a change
// to the engine's wording fails this test instead of silently hiding the
// decision from the director.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/pairing_review.dart';

TournamentController open(int players, int rounds) {
  final c = TournamentController(SqliteEventRepository(':memory:'));
  c.create('Club Open');
  c.importPlayers([
    for (var i = 0; i < players; i++)
      Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 50),
  ]);
  c.addSection('Open', Format.swiss, rounds);
  return c;
}

Round latest(TournamentController c) => c.event!.sections.single.rounds.last;

/// The engine's explanation of [kind] in [batch], which must also be among
/// the notes shown after posting.
String reviewed(
  TournamentController c,
  PairingBatch batch,
  PairingReview kind,
) {
  final lines = [
    for (final round in batch.rounds.values) ...round.explanations,
  ];
  final hits = lines.where((line) => PairingReview.of(line) == kind);
  expect(hits, isNotEmpty, reason: 'engine said:\n${lines.join('\n')}');
  expect(postReviewNotes(c.event!, batch), contains('Open: ${hits.first}'));
  return hits.first;
}

void main() {
  test('every marker is still a phrase of the Swiss engine', () {
    final engine = File('lib/domain/swiss_pairing.dart').readAsStringSync();
    for (final kind in PairingReview.values) {
      expect(engine, contains(kind.marker), reason: kind.name);
    }
  });

  test('a routine explanation is not a review note', () async {
    final c = open(8, 3);
    addTearDown(c.dispose);
    final batch = await c.propose();
    expect(postReviewNotes(c.event!, batch), isEmpty);
    expect(PairingReview.of('Transposed boards 2 and 3 for color.'), isNull);
  });

  test('a repeat meeting (27A1) is recognised', () async {
    // Four players meet everyone in three rounds; round 4 must repeat.
    final c = open(4, 4);
    addTearDown(c.dispose);
    for (var r = 0; r < 3; r++) {
      c.post(await c.propose());
      for (final g in latest(c).games) {
        c.recordResult(g.id, Outcome.draw);
      }
    }
    final line = reviewed(c, await c.propose(), PairingReview.repeatMeeting);
    expect(line, contains('27A1'));
  });

  test('a second bye (28L3) is recognised', () async {
    // Three players: after three rounds each has had the bye.
    final c = open(3, 4);
    addTearDown(c.dispose);
    for (var r = 0; r < 3; r++) {
      c.post(await c.propose());
      for (final g in latest(c).games) {
        c.recordResult(g.id, Outcome.draw);
      }
    }
    final line = reviewed(c, await c.propose(), PairingReview.repeatBye);
    expect(line, contains('28L3'));
  });

  test('a third color in a row (29E5f) is recognised', () async {
    // Two rounds in which p0 and p2 had white twice and p1 and p3 black
    // twice leave one pairing without a repeat: p0-p2 and p1-p3, each of
    // which gives someone the same color a third time.
    final c = open(4, 3);
    addTearDown(c.dispose);
    final id = c.event!.sections.single.id;
    for (final pairs in [
      [('p0', 'p1'), ('p2', 'p3')],
      [('p0', 'p3'), ('p2', 'p1')],
    ]) {
      c.post(await c.propose());
      final round = latest(c);
      c.replacePairing(id, round.number, [
        for (final (i, g) in round.games.indexed)
          g.copy(white: pairs[i].$1, black: pairs[i].$2),
      ], 'Set up colors');
      for (final g in latest(c).games) {
        c.recordResult(g.id, Outcome.draw);
      }
    }
    final line = reviewed(c, await c.propose(), PairingReview.thirdColor);
    expect(line, contains('29E5f'));
  });

  test('a pairing found by search (29D2, 29E5) is recognised', () async {
    // Seeded random events, played until the group-by-group procedure
    // gives up and the search takes over. Seed 13 does so in round 5; the
    // others are tried only if the engine's pairings change.
    for (final seed in [13, for (var i = 0; i < 400; i++) i]) {
      final random = Random(seed);
      final c = open(5 + seed % 6, 6);
      try {
        for (var r = 0; r < 6; r++) {
          final PairingBatch batch;
          try {
            batch = await c.propose();
          } on TournamentException {
            break;
          }
          final found = batch.rounds.values
              .expand((round) => round.explanations)
              .any((l) => PairingReview.of(l) == PairingReview.searchFallback);
          if (found) {
            final line = reviewed(c, batch, PairingReview.searchFallback);
            expect(line, contains('29D2'));
            return;
          }
          try {
            c.post(batch);
          } on TournamentException {
            break;
          }
          for (final g in latest(c).games) {
            c.recordResult(
              g.id,
              const [Outcome.whiteWin, Outcome.blackWin, Outcome.draw][random
                  .nextInt(3)],
            );
          }
        }
      } finally {
        c.dispose();
      }
    }
    fail('No seeded event made the engine fall back to its search.');
  });
}
