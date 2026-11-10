// Replacing or clearing a recorded result with one key is never silent: a
// notice names the board and the change and offers Undo. A first entry
// into an empty box stays quiet.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/result_format.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';
import 'dock_host.dart';

TournamentController open(int players, {Format format = Format.swiss}) {
  final c = TournamentController(SqliteEventRepository(':memory:'));
  c.create('Club Open');
  c.importPlayers([
    for (var i = 0; i < players; i++)
      Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 50),
  ]);
  c.addSection('Open', format, 3);
  return c;
}

Future<void> mount(
  WidgetTester tester,
  TournamentController c, {
  String? sectionId,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: DockHost(
          child: ListenableBuilder(
            listenable: c,
            builder: (_, _) => ResultsView(controller: c, sectionId: sectionId),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump();
}

final notice = find.byKey(const ValueKey('undo-notice'));

void main() {
  Outcome outcome(TournamentController c, String id) =>
      c.event!.games.firstWhere((g) => g.id == id).outcome;

  testWidgets('overwriting a result says so, and Undo puts it back', (
    tester,
  ) async {
    final c = open(8);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final section = c.event!.sections.single;
    final g = section.rounds.single.games.firstWhere((g) => g.board == 1);
    await mount(tester, c, sectionId: section.id);
    await tester.tap(find.byKey(ValueKey('score-${g.id}-w')));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.digit1);
    expect(outcome(c, g.id), Outcome.whiteWin);
    expect(notice, findsNothing, reason: 'a first entry is not an overwrite');

    // A click on the row body arms the same box as a click on the box, and
    // the next key is answered the same way.
    await tester.tapAt(
      tester.getTopLeft(find.byKey(ValueKey('game-${g.id}'))) +
          const Offset(20, 16),
    );
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'score ${g.id} white',
    );
    await press(tester, LogicalKeyboardKey.keyD);
    expect(outcome(c, g.id), Outcome.draw);
    expect(notice, findsOneWidget);
    expect(find.text('Board 1 was 1–0, now ½–½'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(outcome(c, g.id), Outcome.whiteWin);

    // The same result again changes nothing and says nothing.
    await tester.tap(find.byKey(ValueKey('score-${g.id}-w')));
    await tester.pump();
    final before = c.event!.revision;
    await press(tester, LogicalKeyboardKey.digit1);
    expect(c.event!.revision, before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Backspace and Delete clear a result with the notice', (
    tester,
  ) async {
    final c = open(8);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final section = c.event!.sections.single;
    final g = section.rounds.single.games.firstWhere((g) => g.board == 2);
    c.recordResult(g.id, Outcome.blackWin);
    await mount(tester, c, sectionId: section.id);
    await tester.tap(find.byKey(ValueKey('score-${g.id}-b')));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.backspace);
    expect(outcome(c, g.id), Outcome.unreported);
    expect(find.text('Board 2 was 0–1, now no result'), findsOneWidget);
    // The cursor stays on the cleared board.
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'score ${g.id} black',
    );
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(outcome(c, g.id), Outcome.blackWin);
    await tester.tap(find.byKey(ValueKey('score-${g.id}-b')));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.delete);
    expect(outcome(c, g.id), Outcome.unreported);
    expect(find.text('Board 2 was 0–1, now no result'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a forfeit replaced by a played result is named as a forfeit', (
    tester,
  ) async {
    expect(resultText(Outcome.whiteForfeit), '1–F');
    expect(resultText(Outcome.blackForfeit), 'F–1');
    expect(resultText(Outcome.doubleForfeit), 'F–F');
    expect(
      resultChangeText(4, Outcome.unfinished, Outcome.draw),
      'Board 4 was still playing, now ½–½',
    );
  });

  testWidgets('the event-wide grid names the section in the notice', (
    tester,
  ) async {
    final c = fixture(count: 8, format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final section = c.event!.sections.last;
    final g = section.rounds.single.games.first;
    c.recordResult(g.id, Outcome.whiteWin);
    await mount(tester, c);
    await tester.tap(find.byKey(ValueKey('score-${g.id}-w')));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.digit0);
    expect(outcome(c, g.id), Outcome.blackWin);
    expect(
      find.text('${section.name} · Board ${g.board} was 1–0, now 0–1'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'an earlier round of a round robin is entered like the current round',
    (tester) async {
      final c = open(6, format: Format.roundRobin);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final first = c.event!.sections.single.rounds.single;
      for (final g in first.games) {
        c.recordResult(g.id, Outcome.whiteWin);
      }
      c.post((await tester.runAsync(() => c.propose()))!);
      final section = c.event!.sections.single;
      expect(section.rounds.length, 2);
      await mount(tester, c, sectionId: section.id);
      await tester.tap(find.widgetWithText(ChoiceChip, '1'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('past-round-banner')), findsNothing);
      final g = first.games.firstWhere((g) => g.board == 1);
      await tester.tap(find.byKey(ValueKey('score-${g.id}-w')));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.keyD);
      expect(outcome(c, g.id), Outcome.draw);
      expect(
        find.byKey(const ValueKey('result-correction-review')),
        findsNothing,
      );
      expect(find.text('Round 1 · Board 1 was 1–0, now ½–½'), findsOneWidget);
      await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
      await tester.pumpAndSettle();
      expect(outcome(c, g.id), Outcome.whiteWin);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
