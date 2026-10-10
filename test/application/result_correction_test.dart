import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/history.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import '../support.dart';

void finish(TournamentController c, String section) {
  for (final g
      in c.event!.sections
          .firstWhere((s) => s.id == section)
          .rounds
          .last
          .games) {
    c.recordResult(g.id, Outcome.whiteWin);
  }
}

Future<String> twoRounds(TournamentController c) async {
  final id = c.event!.sections.first.id;
  c.post(await c.propose(sectionId: id));
  finish(c, id);
  c.post(await c.propose(sectionId: id));
  return id;
}

void main() {
  test(
    'keep pairings corrects only the game and preserves current roster edits',
    () async {
      final c = fixture();
      addTearDown(c.dispose);
      final id = await twoRounds(c);
      final g = c.event!.sections.first.rounds.first.games.first;
      c.savePlayer(
        c.event!
            .player(g.white)
            .copy(name: 'Corrected name', notes: 'Walk-up update'),
      );
      final before = c.event!;
      final revision = before.revision;
      final review = c.reviewResult(g.id);
      c.correctResult(review, Outcome.draw, reason: 'Checked scoresheet');
      expect(c.event!.revision, revision + 1);
      expect(c.event!.player(g.white).name, 'Corrected name');
      expect(c.event!.player(g.white).notes, 'Walk-up update');
      final section = c.event!.sections.firstWhere((s) => s.id == id);
      expect(
        jsonEncode(section.rounds.last.toJson()),
        jsonEncode(before.sections.first.rounds.last.toJson()),
      );
      expect(
        jsonEncode(c.event!.sections.last.toJson()),
        jsonEncode(before.sections.last.toJson()),
      );
      expect(section.rounds.first.games.first.outcome, Outcome.draw);
      expect(section.rounds.first.games.first.note, 'Checked scoresheet');
      expect(
        c.graph.nodes[c.graph.head]!.action,
        allOf(contains('½–½'), contains('Checked scoresheet')),
      );
    },
  );

  test(
    'reopen and correction are atomic and survive restart with their previous version',
    () async {
      final dir = Directory.systemTemp.createTempSync('meow-correction-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/event.meow';
      final c = fixture(path: path);
      final id = await twoRounds(c);
      final g = c.event!.sections.first.rounds.first.games.first;
      final before = c.graph.head!;
      final revision = c.event!.revision;
      final review = c.reviewResult(g.id);
      expect(
        () => c.correctResult(
          review,
          Outcome.blackWin,
          reason: 'Signed slip',
          reopenFrom: 2,
        ),
        throwsA(isA<TournamentException>()),
      );
      expect(c.event!.revision, revision);
      c.correctResult(
        review,
        Outcome.blackWin,
        reason: 'Signed slip',
        reopenFrom: 2,
        confirmedUnstarted: true,
      );
      expect(c.event!.revision, revision + 1);
      expect(c.event!.sections.first.rounds.length, 1);
      expect(c.graph.nodes[c.graph.head]!.parent, before);
      final corrected = c.graph.head!;
      c.dispose();
      final reopened = TournamentController(SqliteEventRepository(path));
      addTearDown(reopened.dispose);
      expect(reopened.graph.head, corrected);
      expect(
        reopened.event!.sections.first.rounds.first.games.first.outcome,
        Outcome.blackWin,
      );
      expect(
        reopened.repository.snapshot(before).sections.first.rounds.length,
        2,
      );
      reopened.undo();
      expect(reopened.event!.sections.first.rounds.length, 2);
      expect(
        reopened.event!.sections.first.rounds.first.games.first.outcome,
        Outcome.whiteWin,
      );
      reopened.redo();
      expect(reopened.event!.sections.first.rounds.length, 1);
      final batch = await reopened.propose(sectionId: id);
      expect(batch.rounds[id]!.number, 2);
    },
  );

  test(
    'recorded play protects a whole suffix, while an unstarted tail can reopen',
    () async {
      final c = fixture();
      addTearDown(c.dispose);
      final id = await twoRounds(c);
      final g = c.event!.sections.first.rounds.first.games.first;
      c.startRound(id);
      finish(c, id);
      c.post(await c.propose(sectionId: id));
      final review = c.reviewResult(g.id);
      expect(review.canReopenFrom(2), false);
      expect(review.canReopenFrom(3), true);
      final before = c.event!.encode();
      expect(
        () => c.correctResult(
          review,
          Outcome.draw,
          reason: 'Correction',
          reopenFrom: 2,
          confirmedUnstarted: true,
        ),
        throwsA(isA<TournamentException>()),
      );
      expect(c.event!.encode(), before);
      c.correctResult(
        review,
        Outcome.draw,
        reason: 'Correction',
        reopenFrom: 3,
        confirmedUnstarted: true,
      );
      expect(c.event!.sections.first.rounds.length, 2);
      expect(c.event!.sections.first.rounds.last.startedAt, isNotNull);
      expect(c.event!.sections.first.rounds.last.complete, true);
    },
  );

  test(
    'all nonblank outcomes protect play, including disputed and unfinished games',
    () async {
      // ½–0, 0–½ and a played 0–0 are refused where US Chess rates the
      // section (see the unusual-results test).
      for (final outcome in Outcome.values.where(
        (o) => o != Outcome.unreported && !o.unusual,
      )) {
        final c = fixture();
        try {
          await twoRounds(c);
          final section = c.event!.sections.first;
          c.recordResult(section.rounds.last.games.first.id, outcome);
          expect(
            c
                .reviewResult(section.rounds.first.games.first.id)
                .canReopenFrom(2),
            false,
            reason: outcome.name,
          );
        } finally {
          c.dispose();
        }
      }
    },
  );

  test(
    'reopening a boundary removes every unstarted dependent round',
    () async {
      final c = fixture();
      addTearDown(c.dispose);
      final id = await twoRounds(c);
      final first = c.event!.games.first;
      for (final g in c.event!.sections.first.rounds.last.games) {
        c.setPairingAssumption(g.id, Outcome.draw, 'Pairing preview only');
      }
      c.post(await c.propose(sectionId: id));
      final review = c.reviewResult(first.id);
      expect(review.later.map((r) => r.number), [2, 3]);
      expect(review.canReopenFrom(2), true);
      expect(review.canReopenFrom(3), true);
      final saved = c.graph.head!;
      c.correctResult(
        review,
        Outcome.draw,
        reason: 'Correct before play',
        reopenFrom: 2,
        confirmedUnstarted: true,
      );
      expect(c.event!.sections.first.rounds.map((r) => r.number), [1]);
      expect(c.repository.snapshot(saved).sections.first.rounds.length, 3);
    },
  );

  test(
    'stale reviews cannot overwrite new results or player changes',
    () async {
      final c = fixture();
      addTearDown(c.dispose);
      await twoRounds(c);
      final review = c.reviewResult(c.event!.games.first.id);
      c.savePlayer(c.event!.player('p0').copy(notes: 'New information'));
      final before = c.event!.encode();
      expect(
        () => c.correctResult(review, Outcome.draw, reason: 'Old review'),
        throwsA(isA<TournamentException>()),
      );
      expect(c.event!.encode(), before);
    },
  );

  test(
    'source result detects transferred scores even without later source rounds',
    () async {
      final c = fixture();
      addTearDown(c.dispose);
      c.post(await c.propose());
      for (final s in c.event!.sections) {
        finish(c, s.id);
      }
      final source = c.event!.sections.first;
      final target = c.event!.sections.last;
      c.movePlayers(source.players, target.id, reason: 'Combine sections');
      c.post(await c.propose(sectionId: target.id));
      final review = c.reviewResult(source.rounds.first.games.first.id);
      expect(review.later, isEmpty);
      expect(review.hasDependencies, true);
      expect(review.hasTransfers, true);
      expect(review.relatedRounds.single.$1.id, target.id);
      expect(review.relatedRounds.single.$2.number, 2);
      final before = jsonEncode(c.event!.sections.last.toJson());
      c.correctResult(
        review,
        Outcome.draw,
        reason: 'Correct transferred score',
      );
      expect(jsonEncode(c.event!.sections.last.toJson()), before);
    },
  );

  test(
    'selective result undo targets stable identity and keeps later transactions',
    () async {
      final c = fixture();
      addTearDown(c.dispose);
      c.post(await c.propose());
      final g = c.event!.games.first;
      final before = c.event!;
      c.recordResult(g.id, Outcome.whiteWin);
      final after = c.event!;
      finish(c, c.event!.sections.first.id);
      c.post(await c.propose(sectionId: c.event!.sections.first.id));
      c.savePlayer(c.event!.player('p0').copy(notes: 'Keep me'));
      final undo = reversibleResult(before, after, c.event!);
      expect(undo, (gameId: g.id, outcome: Outcome.unreported));
      c.correctResult(
        c.reviewResult(undo!.gameId),
        undo.outcome,
        reason: 'Undo selected result',
      );
      expect(c.event!.games.first.outcome, Outcome.unreported);
      expect(c.event!.sections.first.rounds.length, 2);
      expect(c.event!.player('p0').notes, 'Keep me');
      expect(reversibleResult(before, after, c.event!), isNull);
      expect(reversibleResult(before, c.event!, c.event!), isNull);
    },
  );
}
