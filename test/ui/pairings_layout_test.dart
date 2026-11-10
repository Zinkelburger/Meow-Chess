// The Pairings page keeps still while results are typed, says what to do
// when there is nothing to pair, and names only what is read-only.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';
import 'dock_host.dart';

class CountingPreferences extends SqliteEventRepository {
  CountingPreferences() : super(':memory:');
  final writes = <String, int>{};
  @override
  void writePreference(String key, String value) {
    writes[key] = (writes[key] ?? 0) + 1;
    super.writePreference(key, value);
  }
}

TournamentController open(
  int players, {
  String Function(int)? name,
  SqliteEventRepository? repository,
}) {
  final c = TournamentController(
    repository ?? SqliteEventRepository(':memory:'),
  );
  c.create('Club Open');
  c.importPlayers([
    for (var i = 0; i < players; i++)
      Player(
        id: 'p$i',
        name: name?.call(i) ?? 'Player $i',
        rating: 2000 - i * 10,
      ),
  ]);
  c.addSection('Open', Format.swiss, 3);
  return c;
}

Future<void> mount(
  WidgetTester tester,
  TournamentController c,
  Widget Function() view, {
  Size size = const Size(1440, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: DockHost(
          child: ListenableBuilder(listenable: c, builder: (_, _) => view()),
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

void main() {
  for (final size in const [Size(1440, 900), Size(1024, 640)]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('entering the last result moves nothing at '
          '${size.width.toInt()}x${size.height.toInt()}, text ${scale}x', (
        tester,
      ) async {
        final c = open(8);
        addTearDown(c.dispose);
        c.post((await tester.runAsync(() => c.propose()))!);
        final section = c.event!.sections.single;
        final games = [...section.rounds.single.games]
          ..sort((a, b) => a.board.compareTo(b.board));
        for (final g in games.take(games.length - 1)) {
          c.recordResult(g.id, Outcome.whiteWin);
        }
        await mount(
          tester,
          c,
          () => ResultsView(controller: c, sectionId: section.id),
          size: size,
          textScale: scale,
        );
        final box = find.byKey(ValueKey('score-${games.last.id}-w'));
        await tester.ensureVisible(box);
        await tester.pumpAndSettle();
        await tester.tap(box);
        await tester.pump();
        final tracked = [
          for (final key in [
            'board-column-header',
            'player-column-header',
            'board-search',
            'print-round',
            'result-legend',
            'score-${games.first.id}-w',
          ])
            find.byKey(ValueKey(key)),
        ];
        final before = [for (final f in tracked) tester.getTopLeft(f)];
        final legend = tester.getSize(
          find.byKey(const ValueKey('result-legend')),
        );
        await press(tester, LogicalKeyboardKey.digit1);
        await tester.pumpAndSettle();
        expect(c.event!.games.every((g) => g.outcome.resolved), isTrue);
        expect(
          find.byKey(const ValueKey('all-results-entered')),
          findsOneWidget,
        );
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'all results entered',
        );
        expect([for (final f in tracked) tester.getTopLeft(f)], before);
        expect(
          tester.getSize(find.byKey(const ValueKey('result-legend'))),
          legend,
        );
        expect(tester.takeException(), isNull);
        // The next key changes nothing.
        final saved = c.event!.encode();
        await press(tester, LogicalKeyboardKey.digit0);
        expect(c.event!.encode(), saved);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('a long context line wraps instead of losing whose result is '
      'being entered', (tester) async {
    final c = open(4, name: (i) => 'Featherstonehaugh $i');
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final section = c.event!.sections.single;
    final g = section.rounds.single.games.first;
    await mount(
      tester,
      c,
      () => ResultsView(controller: c, sectionId: section.id),
      size: const Size(1024, 640),
    );
    final legend = find.byKey(const ValueKey('result-legend'));
    await tester.ensureVisible(legend);
    await tester.pumpAndSettle();
    final idle = tester.getSize(legend).height;
    await tester.tap(find.byKey(ValueKey('score-${g.id}-b')));
    await tester.pumpAndSettle();
    final context = find.byKey(const ValueKey('entry-context'));
    expect(
      tester.widget<Text>(context).data,
      endsWith("entering Black's result"),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: context, matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    // One line would not hold it; the second is always reserved, so taking
    // focus moves nothing under the boards.
    expect(paragraph.size.height, greaterThan(26));
    expect(tester.getSize(legend).height, idle);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with no players the page says to add them', (tester) async {
    final c = TournamentController(SqliteEventRepository(':memory:'));
    addTearDown(c.dispose);
    c.create('Club Open');
    var asked = 0;
    await mount(
      tester,
      c,
      () => ResultsView(controller: c, onAddPlayers: () => asked++),
    );
    expect(
      find.text(
        'Add players on the Players page, then create a section to pair them.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('blank-board-sheet')), findsNothing);
    expect(find.text('No matching boards'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('empty-add-players')));
    expect(asked, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with players but no section the page says to create one', (
    tester,
  ) async {
    final c = TournamentController(SqliteEventRepository(':memory:'));
    addTearDown(c.dispose);
    c.create('Club Open');
    c.importPlayers([
      for (var i = 0; i < 6; i++)
        Player(id: 'p$i', name: 'Player $i', rating: 1500),
    ]);
    var asked = 0;
    await mount(
      tester,
      c,
      () => ResultsView(controller: c, onNewSection: () => asked++),
      size: const Size(1024, 640),
    );
    expect(
      find.text('Create a section to pair these players.'),
      findsOneWidget,
    );
    expect(find.text('No matching boards'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('empty-new-section')));
    expect(asked, 1);
    // Without a way there, the words stand alone.
    await mount(tester, c, () => ResultsView(controller: c));
    expect(find.byKey(const ValueKey('empty-new-section')), findsNothing);
    expect(
      find.text('Create a section to pair these players.'),
      findsOneWidget,
    );
    // A section that is not paired yet shows its blank board sheet.
    c.addSection('Open', Format.swiss, 3);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('blank-board-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('nothing-to-pair')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a round without boards is not reported as a failed search', (
    tester,
  ) async {
    final c = open(8);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final section = c.event!.sections.single;
    // Every game removed from the posted round: nothing to list.
    c.change(
      'Empty round',
      c.event!.copy(
        sections: [
          section.copy(rounds: [section.rounds.single.copy(games: const [])]),
        ],
      ),
    );
    await mount(
      tester,
      c,
      () => ResultsView(controller: c, sectionId: section.id),
    );
    expect(find.text('No matching boards'), findsNothing);
    expect(find.text('No boards in this round'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the banner names only the round that is read-only', (
    tester,
  ) async {
    final c = fixture(count: 8, format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final [ahead, behind] = c.event!.sections;
    for (final g in ahead.rounds.single.games) {
      c.recordResult(g.id, Outcome.whiteWin);
    }
    c.post((await tester.runAsync(() => c.propose(sectionId: ahead.id)))!);
    await mount(tester, c, () => ResultsView(controller: c));
    final banner = find.byKey(const ValueKey('past-round-banner'));
    expect(banner, findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '1'));
    await tester.pumpAndSettle();
    // Round 1 of the section already on round 2 is locked; the other
    // section's round 1 is its current round.
    expect(
      find.descendant(
        of: banner,
        matching: find.text('${ahead.name} round 1 is read-only'),
      ),
      findsOneWidget,
    );
    expect(find.text('Read-only'), findsNothing);
    expect(find.byKey(const ValueKey('correct-round')), findsOneWidget);
    final open = behind.rounds.single.games.first;
    await tester.tap(find.byKey(ValueKey('score-${open.id}-w')));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.digit1);
    expect(
      c.event!.games.firstWhere((g) => g.id == open.id).outcome,
      Outcome.whiteWin,
    );
    final locked = ahead.rounds.single.games.first;
    await tester.tap(find.byKey(ValueKey('score-${locked.id}-w')));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.digit0);
    expect(
      c.event!.games.firstWhere((g) => g.id == locked.id).outcome,
      Outcome.whiteWin,
    );
    expect(
      find.text(
        '${ahead.name} round 1 is read-only · choose Correct a result to '
        'change it',
      ),
      findsOneWidget,
    );
    // On its own, that round is simply read-only.
    await mount(
      tester,
      c,
      () => ResultsView(controller: c, sectionId: ahead.id),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '1'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: banner, matching: find.text('Read-only')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the boards printer says what it prints', (tester) async {
    final c = open(8);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    await mount(
      tester,
      c,
      () => ResultsView(controller: c, sectionId: c.event!.sections.single.id),
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('print-round')))
          .tooltip,
      'Print pairings and result sheets for this round',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scrolling the boards saves once it settles, not on every tick', (
    tester,
  ) async {
    final repository = CountingPreferences();
    final c = open(120, repository: repository);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final section = c.event!.sections.single;
    final preference = 'results-${section.id}';
    await mount(
      tester,
      c,
      () => ResultsView(controller: c, sectionId: section.id),
      size: const Size(1920, 1080),
    );
    await tester.pump(const Duration(seconds: 1));
    final state = tester.state<ResultsViewState>(find.byType(ResultsView));
    expect(state.scroll.hasClients, isTrue);
    expect(state.scroll.position.maxScrollExtent, greaterThan(600));
    final settled = repository.writes[preference] ?? 0;
    for (var offset = 40.0; offset <= 600; offset += 40) {
      state.scroll.jumpTo(offset);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      repository.writes[preference] ?? 0,
      settled,
      reason: 'nothing is written while the list is moving',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.writes[preference], settled + 1);
    expect(c.workspaceState.readMap(preference)['scroll'], 600);
    // A rebuild that changes nothing costs no write either.
    c.workspaceState.write('unrelated', 'x');
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.writes[preference], settled + 1);
    // Leaving the page still saves where it was, even mid-scroll.
    state.scroll.jumpTo(320);
    await tester.pumpWidget(const SizedBox());
    expect(c.workspaceState.readMap(preference)['scroll'], 320);
  });
}
