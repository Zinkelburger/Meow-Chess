import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/infrastructure/dbf_export.dart';
import '../support.dart';

void main() {
  test(
    'historical scope excludes later rounds and points, retaining revision',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      for (var round = 0; round < 2; round++) {
        c.post(await c.propose());
        for (final game in c.event!.sections.single.rounds.last.games) {
          c.recordResult(game.id, Outcome.draw);
        }
      }
      final historical = eventThroughRound(c.event!, 1);
      expect(historical.revision, c.event!.revision);
      expect(historical.sections.single.rounds, hasLength(1));
      expect(
        reportStandings(
          historical,
          historical.sections.single,
        ).map((s) => s.points).toSet(),
        {1},
      );
      expect(
        reportStandings(
          c.event!,
          c.event!.sections.single,
        ).map((s) => s.points).toSet(),
        {2},
      );
      expect(
        () => eventThroughRound(c.event!, 3),
        throwsA(isA<TournamentException>()),
      );
      expect(eventThroughRound(c.event!, 0).games, isEmpty);
    },
  );

  test(
    'refresh refuses removed sections and rounds instead of silently changing scope',
    () async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final section = c.event!.sections.single;
      await expectLater(
        reportPdf(c.event!, ReportKind.packet, roundNumbers: {section.id: 1}),
        throwsA(isA<TournamentException>()),
      );
      await expectLater(
        reportPdf(
          c.event!.copy(sections: []),
          ReportKind.packet,
          roundNumbers: {section.id: 0},
        ),
        throwsA(isA<TournamentException>()),
      );
    },
  );

  test('printed prize class re-ranks its own players', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final rows = reportStandings(
      c.event!,
      c.event!.sections.single,
      ceiling: 1950,
    );
    expect(rows.map((s) => s.player.rating), [1900, 1850]);
    expect(rows.map((s) => s.rank), [1, 1]);
  });

  test(
    'report issues retain player identities and exact repair destinations',
    () {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.savePlayer(c.event!.players.first.copy(memberId: ''));
      final issues = ratingIssues(c.event!);
      expect(issues.map((i) => i.message), ratingPreflight(c.event!));
      final actions = issues.expand((i) => i.repairs);
      expect(
        actions.any(
          (a) =>
              a.destination == ReportDestination.player &&
              a.id == 'p0' &&
              a.field == 'memberId',
        ),
        true,
      );
      expect(
        actions.any(
          (a) => a.destination == ReportDestination.event && a.field == 'td',
        ),
        true,
      );
      expect(
        actions.any(
          (a) =>
              a.destination == ReportDestination.results &&
              a.id == c.event!.sections.single.id,
        ),
        true,
      );
    },
  );
}
