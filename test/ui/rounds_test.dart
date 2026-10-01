import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/results_view.dart';
import '../support.dart';

Future<void> mount(
  WidgetTester tester,
  TournamentController c, {
  String? sectionId,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: c,
          builder: (_, _) => ResultsView(controller: c, sectionId: sectionId),
        ),
      ),
    ),
  );
  await tester.pump();
}

String roundLine(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('round-line')))
    .textSpan!
    .toPlainText();

void finish(TournamentController c, String sectionId) {
  final s = c.event!.sections.firstWhere((s) => s.id == sectionId);
  for (final g in s.rounds.last.games) {
    c.recordResult(g.id, Outcome.whiteWin);
  }
}

/// Nine players in one Swiss, so every round has a bye.
TournamentController swiss() {
  final c = TournamentController(SqliteEventRepository(':memory:'));
  c.create('Tuesday Swiss');
  c.importPlayers([
    for (var i = 0; i < 9; i++)
      Player(id: 's$i', name: 'Swiss $i', rating: 1800 - i * 50),
  ]);
  c.addSection('Open', Format.swiss, 3);
  return c;
}

void main() {
  testWidgets('the round line names the round, its clock and the count in', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final s = c.event!.sections.first;
    await mount(tester, c, sectionId: s.id);
    expect(roundLine(tester), contains('Round 1 of ${s.plannedRounds}'));
    expect(roundLine(tester), contains('Posted '));
    expect(roundLine(tester), contains('Not started'));
    expect(roundLine(tester), contains('0 of 2 in'));
    // Posting is the last change, so it can be taken back from here.
    expect(find.byKey(const ValueKey('undo-post')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('start-round')));
    await tester.pump();
    expect(c.event!.sections.first.rounds.last.startedAt, isNotNull);
    expect(roundLine(tester), contains('Started '));
    expect(find.byKey(const ValueKey('start-round')), findsNothing);
    expect(find.byKey(const ValueKey('undo-post')), findsNothing);
    expect(find.byKey(const ValueKey('print-round')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Start round in All sections starts every section at once', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final before = c.event!.revision;
    await mount(tester, c);
    expect(find.text('Start round · 2 sections'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('start-round')));
    await tester.pump();
    expect(
      c.event!.sections.every((s) => s.rounds.last.startedAt != null),
      true,
    );
    expect(c.event!.revision, before + 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'an earlier round is read-only until Correct a result, and posting resets the view',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      final id = c.event!.sections.first.id;
      c.post((await tester.runAsync(() => c.propose(sectionId: id)))!);
      finish(c, id);
      c.post((await tester.runAsync(() => c.propose(sectionId: id)))!);
      await mount(tester, c, sectionId: id);
      expect(roundLine(tester), contains('Round 2'));
      expect(find.byKey(const ValueKey('past-round-banner')), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('round-selector')),
          matching: find.text('1'),
        ),
      );
      await tester.pump();
      expect(roundLine(tester), contains('Round 1'));
      expect(find.byKey(const ValueKey('past-round-banner')), findsOneWidget);
      final first = c.event!.sections.first.rounds.first.games.first;
      await tester.tap(find.byKey(ValueKey('score-${first.id}-w')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pump();
      // Nothing changed; the banner says how to change it.
      expect(
        c.event!.sections.first.rounds.first.games.first.outcome,
        Outcome.whiteWin,
      );
      expect(
        find.textContaining('Choose Correct a result to change it'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('correct-round')));
      await tester.pump();
      expect(find.textContaining('Correcting round 1'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('score-${first.id}-w')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pump();
      // Round 2 is paired, so the correction asks for a reason first.
      expect(find.byKey(const ValueKey('result-reason')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('result-reason')),
        'Scoresheet signed the other way',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        c.event!.sections.first.rounds.first.games.first.outcome,
        Outcome.blackWin,
      );

      // A new round on the wall puts the page back on the current round.
      finish(c, id);
      c.post((await tester.runAsync(() => c.propose(sectionId: id)))!);
      await tester.pump();
      expect(roundLine(tester), contains('Round 3'));
      expect(find.byKey(const ValueKey('past-round-banner')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('byes come first, and Swiss boards sit in score groups', (
    tester,
  ) async {
    final c = swiss();
    addTearDown(c.dispose);
    final id = c.event!.sections.single.id;
    c.post((await tester.runAsync(() => c.propose()))!);
    await mount(tester, c, sectionId: id);
    final bye = c.event!.sections.single.rounds.last.byes.single;
    final firstGame = c.event!.sections.single.rounds.last.games.first;
    expect(
      tester.getTopLeft(find.byKey(ValueKey('bye-${bye.player}'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(ValueKey('game-${firstGame.id}'))).dy,
      ),
    );
    // Round 1: everyone is on zero, so there are no groups yet.
    expect(find.text('0 points'), findsNothing);

    finish(c, id);
    c.post((await tester.runAsync(() => c.propose()))!);
    await tester.pump();
    expect(find.text('1 point'), findsWidgets);
    expect(find.text('0 points'), findsWidgets);
    expect(
      tester.getTopLeft(find.text('1 point').first).dy,
      lessThan(tester.getTopLeft(find.text('0 points').first).dy),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unfinished and assumed results are marked, not blank', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final [a, b, ...] = c.event!.sections.first.rounds.last.games;
    c.recordResult(a.id, Outcome.unfinished);
    c.setPairingAssumption(b.id, Outcome.draw, 'Long endgame');
    await mount(tester, c, sectionId: c.event!.sections.first.id);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('score-${a.id}-w')),
        matching: find.text('playing'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('score-${b.id}-b')),
        matching: find.text('(½)'),
      ),
      findsOneWidget,
    );
    expect(find.text('assumed'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });
}
