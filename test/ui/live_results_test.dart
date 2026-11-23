import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/posted_results.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/live_results.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';

import '../support.dart';

const url = 'https://beta.boylstonchess.org/results';

/// The website's page for [round] of the event's first section, with the
/// [results] it shows by board.
List<PostedRound> pageOf(
  TournamentController c, {
  int round = 1,
  Map<int, (String, String)> results = const {},
}) {
  final e = c.pairingEvent, s = e.sections.first;
  return [
    PostedRound(
      section: s.name,
      round: round,
      games: [
        for (final g in s.rounds.firstWhere((r) => r.number == round).games)
          PostedGame(
            board: g.board,
            white: e.player(g.white).name,
            black: e.player(g.black).name,
            whiteResult: results[g.board]?.$1 ?? '',
            blackResult: results[g.board]?.$2 ?? '',
          ),
      ],
    ),
  ];
}

Future<TournamentController> swiss() async {
  final c = fixture(count: 4, format: Format.swiss);
  c.post(await c.propose());
  return c;
}

/// Marks the event as imported from Boylston's entry list, which is what
/// puts Website results on the Pairings toolbar.
void fromBoylston(TournamentController c) => c.change(
  'Imported from the club website',
  c.event!.copy(
    rosterSource: {'url': 'https://boylstonchess.org/tournament/entries/1563'},
  ),
);

const button = ValueKey('live-results-button');

Game board(TournamentController c, int number) =>
    c.event!.games.firstWhere((g) => g.board == number);

void main() {
  test('each website result is its own step, named for its source', () async {
    final c = await swiss();
    addTearDown(c.dispose);
    final revision = c.event!.revision;
    final first = board(c, 1).id, second = board(c, 2).id;
    final skipped = c.recordPostedResults({
      first: Outcome.whiteWin,
      second: Outcome.draw,
    }, source: 'beta.boylstonchess.org');
    expect(skipped, isEmpty);
    expect(c.event!.revision, revision + 2);
    expect(board(c, 1).outcome, Outcome.whiteWin);
    expect(board(c, 2).outcome, Outcome.draw);
    final g = board(c, 2);
    expect(
      c.graph.nodes[c.graph.head]!.action,
      'Result from beta.boylstonchess.org, ${c.event!.sections.first.name} '
      'round 1 board 2: ${c.event!.player(g.white).name} – '
      '${c.event!.player(g.black).name}',
    );
    // An ordinary Undo, with nothing to confirm, takes back the latest.
    c.undo();
    expect(board(c, 1).outcome, Outcome.whiteWin);
    expect(board(c, 2).outcome, Outcome.unreported);
    c.undo();
    expect(board(c, 1).outcome, Outcome.unreported);
  });

  test(
    'a board that already has a result is left alone and reported',
    () async {
      final c = await swiss();
      addTearDown(c.dispose);
      final first = board(c, 1).id;
      c.recordResult(first, Outcome.draw);
      final revision = c.event!.revision;
      expect(
        c.recordPostedResults({
          first: Outcome.whiteWin,
          'no-such-game': Outcome.draw,
        }, source: 'the website'),
        [first, 'no-such-game'],
      );
      expect(board(c, 1).outcome, Outcome.draw);
      expect(c.event!.revision, revision);
    },
  );

  test('a result for a quad round not yet saved saves the round first', () {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    expect(c.event!.sections.single.rounds, isEmpty);
    final game = c.pairingEvent.sections.single.rounds[1].games.first;
    c.recordPostedResults({game.id: Outcome.blackWin}, source: 'the website');
    final rounds = c.event!.sections.single.rounds;
    expect(rounds.map((r) => r.number), [1, 2]);
    expect(
      rounds[1].games.firstWhere((g) => g.id == game.id).outcome,
      Outcome.blackWin,
    );
  });

  test('a reading enters what the website has and says what it took', () async {
    final c = await swiss();
    addTearDown(c.dispose);
    var page = pageOf(c);
    final said = <String>[];
    final live = LiveResults(
      c,
      loader: (_) async => page,
      onTaken: said.add,
      interval: const Duration(hours: 1),
      now: () => DateTime(2026, 11, 21, 12, 3, 10),
    );
    addTearDown(live.dispose);
    expect(live.on, isFalse);
    live.start('https://beta.boylstonchess.org/monitor');
    expect(live.url, url);
    await live.check();
    expect(live.checkedAt, DateTime(2026, 11, 21, 12, 3, 10));
    expect(live.reading.following, ['${c.event!.sections.first.name} round 1']);
    expect(
      c.event!.games.every((g) => g.outcome == Outcome.unreported),
      isTrue,
    );
    expect(said, isEmpty);

    page = pageOf(c, results: {2: ('0', '1')});
    final revision = c.event!.revision;
    await live.check();
    expect(board(c, 2).outcome, Outcome.blackWin);
    expect(board(c, 1).outcome, Outcome.unreported);
    expect(c.event!.revision, revision + 1);
    final g = board(c, 2);
    expect(
      said.single,
      'Board 2, ${c.event!.player(g.white).name} – '
      '${c.event!.player(g.black).name}: 0–1, from beta.boylstonchess.org.',
    );

    // The same page again changes nothing.
    await live.check();
    expect(c.event!.revision, revision + 1);
    expect(said, hasLength(1));
  });

  test(
    'several results in one reading say which one Undo takes back',
    () async {
      final c = await swiss();
      addTearDown(c.dispose);
      final said = <String>[];
      final live = LiveResults(
        c,
        loader: (_) async => pageOf(c, results: {1: ('1', '0'), 2: ('½', '½')}),
        onTaken: said.add,
        interval: const Duration(hours: 1),
      );
      addTearDown(live.dispose);
      live.start(url);
      await live.check();
      expect(board(c, 1).outcome, Outcome.whiteWin);
      expect(board(c, 2).outcome, Outcome.draw);
      expect(
        said.single,
        '2 results from beta.boylstonchess.org: board 1, board 2. '
        'Undo takes back board 2; the others are in History.',
      );
      c.undo();
      expect(board(c, 2).outcome, Outcome.unreported);
      expect(board(c, 1).outcome, Outcome.whiteWin);
    },
  );

  test('Undo is respected: the result is offered, not entered again', () async {
    final c = await swiss();
    addTearDown(c.dispose);
    final page = pageOf(c, results: {1: ('½', '½')});
    final live = LiveResults(
      c,
      loader: (_) async => page,
      interval: const Duration(hours: 1),
    );
    addTearDown(live.dispose);
    live.start(url);
    await live.check();
    expect(board(c, 1).outcome, Outcome.draw);
    c.undo();
    expect(board(c, 1).outcome, Outcome.unreported);
    // Listed at once, before the next reading.
    expect(live.reading.differences.single.website, Outcome.draw);
    await live.check();
    expect(board(c, 1).outcome, Outcome.unreported);
    live.use(live.reading.differences.single);
    expect(board(c, 1).outcome, Outcome.draw);
    expect(live.reading.differences, isEmpty);
  });

  test(
    'a correction on the website follows only a result taken from it',
    () async {
      final c = await swiss();
      addTearDown(c.dispose);
      var page = pageOf(c, results: {1: ('1', '0')});
      final live = LiveResults(
        c,
        loader: (_) async => page,
        interval: const Duration(hours: 1),
      );
      addTearDown(live.dispose);
      live.start(url);
      await live.check();
      expect(board(c, 1).outcome, Outcome.whiteWin);
      // The players correct it on the website: it follows.
      page = pageOf(c, results: {1: ('0', '1')});
      await live.check();
      expect(board(c, 1).outcome, Outcome.blackWin);
      // The director enters board 2 by hand; the website then disagrees.
      c.recordResult(board(c, 2).id, Outcome.draw);
      page = pageOf(c, results: {1: ('0', '1'), 2: ('1', '0')});
      await live.check();
      expect(board(c, 2).outcome, Outcome.draw);
      final difference = live.reading.differences.single;
      expect(difference.board, 2);
      expect(difference.here, Outcome.draw);
      expect(difference.website, Outcome.whiteWin);
    },
  );

  test('a correction from the website is named for it in History', () async {
    final c = await swiss();
    addTearDown(c.dispose);
    var page = pageOf(c, results: {1: ('1', '0')});
    final live = LiveResults(
      c,
      loader: (_) async => page,
      interval: const Duration(hours: 1),
    );
    addTearDown(live.dispose);
    live.start(url);
    await live.check();
    page = pageOf(c, results: {1: ('0', '1')});
    await live.check();
    expect(board(c, 1).outcome, Outcome.blackWin);
    expect(
      c.graph.nodes[c.graph.head]!.action,
      startsWith('Result from beta.boylstonchess.org, '),
    );
  });

  test(
    'once the next round is paired, the website no longer changes the round',
    () async {
      final c = await swiss();
      addTearDown(c.dispose);
      var page = pageOf(c, results: {1: ('1', '0'), 2: ('½', '½')});
      final live = LiveResults(
        c,
        loader: (_) async => page,
        interval: const Duration(hours: 1),
      );
      addTearDown(live.dispose);
      live.start(url);
      await live.check();
      expect(board(c, 1).outcome, Outcome.whiteWin);
      final roundOne = board(c, 1).id;
      // Round 2 is paired before the club's page moves on.
      c.post(await c.propose());
      final revision = c.event!.revision;
      // A player then changes round 1 on the website.
      page = pageOf(c, results: {1: ('0', '1'), 2: ('½', '½')});
      await live.check();
      Game game() => c.event!.games.firstWhere((g) => g.id == roundOne);
      expect(game().outcome, Outcome.whiteWin);
      expect(c.event!.revision, revision);
      final difference = live.reading.differences.single;
      expect(difference.gameId, roundOne);
      expect(difference.byHand, isTrue);
      expect(difference.describe(nameSection: false), contains('yourself'));
      expect(live.reading.following, isEmpty);
      // Nothing to click: the director enters it on the board.
      live.use(difference);
      expect(game().outcome, Outcome.whiteWin);
    },
  );

  test('website results wait while a round is paired again', () async {
    final c = _Gated(SqliteEventRepository(':memory:'));
    addTearDown(c.dispose);
    c.create('Club Open');
    c.importPlayers([
      for (var i = 0; i < 4; i++)
        Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 50),
    ]);
    c.addSection('Open', Format.swiss, 3);
    c.post(await c.propose());
    final live = LiveResults(
      c,
      loader: (_) async => pageOf(c, results: {1: ('1', '0')}),
      hold: () => c.pairingUnderWay,
      interval: const Duration(hours: 1),
    );
    addTearDown(live.dispose);
    c.gate = Completer<void>();
    final repaired = c.repairRound(c.event!.sections.single.id);
    expect(c.pairingUnderWay, isTrue);
    live.start(url);
    await live.check();
    expect(board(c, 1).outcome, Outcome.unreported);
    c.gate!.complete();
    // Nothing changed the event meanwhile, so the round is paired again.
    await repaired;
    expect(c.pairingUnderWay, isFalse);
    await live.check();
    expect(board(c, 1).outcome, Outcome.whiteWin);
  });

  test('other pairings on the website enter nothing', () async {
    final c = await swiss();
    addTearDown(c.dispose);
    final live = LiveResults(
      c,
      loader: (_) async => [
        PostedRound(
          section: c.event!.sections.first.name,
          round: 1,
          games: const [
            PostedGame(
              board: 1,
              white: 'Last Week',
              black: 'Somebody Else',
              whiteResult: '1',
              blackResult: '0',
            ),
          ],
        ),
      ],
      interval: const Duration(hours: 1),
    );
    addTearDown(live.dispose);
    final revision = c.event!.revision;
    live.start(url);
    await live.check();
    expect(c.event!.revision, revision);
    expect(live.reading.problems.single, contains('other pairings'));
  });

  test('a page that cannot be read changes nothing and is tried again', () async {
    final c = await swiss();
    addTearDown(c.dispose);
    var down = true;
    final live = LiveResults(
      c,
      loader: (_) async => down
          ? throw const TournamentException(
              'Could not reach beta.boylstonchess.org. Check the internet connection.',
            )
          : pageOf(c, results: {1: ('1', '0')}),
      interval: const Duration(hours: 1),
    );
    addTearDown(live.dispose);
    final revision = c.event!.revision;
    live.start(url);
    await live.check();
    expect(live.failure, contains('Could not reach beta.boylstonchess.org'));
    expect(live.failure, endsWith('meanwhile enter results here yourself.'));
    expect(live.on, isTrue);
    expect(c.event!.revision, revision);
    down = false;
    await live.check();
    expect(live.failure, isNull);
    expect(board(c, 1).outcome, Outcome.whiteWin);
  });

  test('results wait while pairings are being made', () async {
    final c = await swiss();
    addTearDown(c.dispose);
    var pairing = true;
    final live = LiveResults(
      c,
      loader: (_) async => pageOf(c, results: {1: ('1', '0')}),
      hold: () => pairing,
      interval: const Duration(hours: 1),
    );
    addTearDown(live.dispose);
    live.start(url);
    await live.check();
    expect(board(c, 1).outcome, Outcome.unreported);
    pairing = false;
    await live.check();
    expect(board(c, 1).outcome, Outcome.whiteWin);
  });

  test('on, the address and what was taken survive reopening', () async {
    final c = await swiss();
    addTearDown(c.dispose);
    final page = pageOf(c, results: {1: ('1', '0')});
    final first = LiveResults(
      c,
      loader: (_) async => page,
      interval: const Duration(hours: 1),
    );
    first.start(url);
    await first.check();
    first.dispose();
    c.undo();

    final second = LiveResults(
      c,
      loader: (_) async => page,
      interval: const Duration(hours: 1),
    );
    addTearDown(second.dispose);
    expect(second.on, isTrue);
    expect(second.url, url);
    await second.check();
    // Still remembered as taken back.
    expect(board(c, 1).outcome, Outcome.unreported);
    second.stop();
    expect(LiveResults(c, loader: (_) async => page).on, isFalse);
  });

  test('only a results page this app can read is accepted', () async {
    final c = await swiss();
    addTearDown(c.dispose);
    final live = LiveResults(c, loader: (_) async => const []);
    addTearDown(live.dispose);
    expect(
      () => live.start('https://example.org/results'),
      throwsA(isA<TournamentException>()),
    );
    expect(live.on, isFalse);
    // With nothing known about the club, Boylston's page is offered.
    expect(live.knownUrl, isNull);
    expect(live.suggestedUrl, url);
  });

  testWidgets('Website results on the Pairings page: choose, follow, stop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    fromBoylston(c);
    c.post((await tester.runAsync(() => c.propose()))!);
    var page = pageOf(c);
    final live = LiveResults(
      c,
      loader: (_) async => page,
      now: () => DateTime(2026, 11, 21, 9, 5, 7),
    );
    addTearDown(live.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => ResultsView(controller: c, liveResults: live),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-results')), findsNothing);
    // Off, the button is the tinted one on the toolbar, with its symbol.
    final colors = meowTheme(Brightness.light).colorScheme;
    Color? fill() => tester
        .widget<OutlinedButton>(find.byKey(button))
        .style!
        .backgroundColor!
        .resolve({});
    expect(fill(), colors.secondaryContainer);
    expect(find.byKey(const ValueKey('live-results-off')), findsOneWidget);
    final place = tester.getRect(find.byKey(button));
    await tester.tap(find.byKey(button));
    await tester.pump();
    await tester.pump();
    expect(live.on, isTrue);
    // On, it is the selected surface with a tick, and has not moved.
    expect(fill(), colors.surfaceContainerHigh);
    expect(find.byKey(const ValueKey('live-results-on')), findsOneWidget);
    expect(tester.getRect(find.byKey(button)), place);
    expect(find.byKey(const ValueKey('live-results')), findsOneWidget);

    // Another page: the one in use is already filled in.
    await tester.tap(find.byKey(const ValueKey('live-results-change')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('live-results-url')))
          .controller!
          .text,
      url,
    );
    expect(live.on, isFalse);

    // An address that is not a results page is refused in place.
    await tester.enterText(
      find.byKey(const ValueKey('live-results-url')),
      'https://example.org/results',
    );
    await tester.tap(find.byKey(const ValueKey('live-results-start')));
    await tester.pump();
    expect(find.byKey(const ValueKey('live-results-error')), findsOneWidget);
    expect(live.on, isFalse);

    await tester.enterText(find.byKey(const ValueKey('live-results-url')), url);
    await tester.tap(find.byKey(const ValueKey('live-results-start')));
    await tester.pump();
    await tester.pump();
    expect(live.on, isTrue);
    final section = c.event!.sections.first.name;
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('live-results-status')))
          .data,
      'Entering results from beta.boylstonchess.org as players report them '
      'there. Following $section round 1. '
      'Read at 09:05:07.',
    );

    // The next reading, ten seconds on, brings a result in.
    page = pageOf(c, results: {1: ('1', '0')});
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(board(c, 1).outcome, Outcome.whiteWin);

    // The director disagrees about board 2; the website's is one click.
    c.recordResult(board(c, 2).id, Outcome.draw);
    page = pageOf(c, results: {1: ('1', '0'), 2: ('0', '1')});
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(board(c, 2).outcome, Outcome.draw);
    final use = find.byKey(ValueKey(('live-results-use', board(c, 2).id)));
    expect(
      find.descendant(of: use, matching: find.text('Use 0–1')),
      findsOneWidget,
    );
    await tester.tap(use);
    await tester.pump();
    expect(board(c, 2).outcome, Outcome.blackWin);
    expect(use, findsNothing);

    await tester.tap(find.byKey(const ValueKey('live-results-stop')));
    await tester.pumpAndSettle();
    expect(live.on, isFalse);
    expect(find.byKey(const ValueKey('live-results')), findsNothing);
    // Dismiss the Undo notice so no timer outlives the test.
    ScaffoldMessenger.of(
      tester.element(find.byType(ResultsView)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();
  });

  testWidgets('an event from Boylston\'s entry list starts with one click', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    fromBoylston(c);
    c.post((await tester.runAsync(() => c.propose()))!);
    final asked = <String>[];
    final live = LiveResults(
      c,
      loader: (address) async {
        asked.add(address);
        return pageOf(c, results: {1: ('1', '0')});
      },
    );
    addTearDown(live.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => ResultsView(controller: c, liveResults: live),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(button));
    await tester.pump();
    await tester.pump();
    // No address to paste: the club's results page is read straight away.
    expect(find.byKey(const ValueKey('live-results-url')), findsNothing);
    expect(live.on, isTrue);
    expect(asked, [url]);
    expect(board(c, 1).outcome, Outcome.whiteWin);

    // Another page can still be chosen, starting from the one in use.
    await tester.tap(find.byKey(const ValueKey('live-results-change')));
    await tester.pumpAndSettle();
    expect(live.on, isFalse);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('live-results-url')))
          .controller!
          .text,
      url,
    );
    // Once used, the button turns the same page back on.
    await tester.tap(find.byKey(button));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-results')), findsNothing);
    await tester.tap(find.byKey(button));
    await tester.pump();
    await tester.pump();
    expect(live.on, isTrue);
    await tester.tap(find.byKey(const ValueKey('live-results-stop')));
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(
      tester.element(find.byType(ResultsView)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();
  });

  testWidgets('only an event from a club website has Website results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final live = LiveResults(c, loader: (_) async => const []);
    addTearDown(live.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => ResultsView(controller: c, liveResults: live),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Players typed in or imported from a file: nothing to take results
    // from, so no button.
    expect(live.available, isFalse);
    expect(find.byKey(button), findsNothing);
    expect(find.text('Website results'), findsNothing);

    // The same event once its players come from Boylston's entry list.
    fromBoylston(c);
    await tester.pumpAndSettle();
    expect(live.available, isTrue);
    expect(find.byKey(button), findsOneWidget);
  });

  testWidgets('in the workspace, results arrive on any page with Undo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    fromBoylston(c);
    c.post((await tester.runAsync(() => c.propose()))!);
    var page = pageOf(c);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Workspace(
          controller: c,
          path: ':memory:',
          onClose: () {},
          onTheme: () {},
          resultsLoader: (_) async => page,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(button));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('live-results-status')), findsOneWidget);

    // Away from Pairings, the next reading still enters the result.
    await tester.tap(find.text('Players').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-results')), findsNothing);
    page = pageOf(c, results: {2: ('½', '½')});
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(board(c, 2).outcome, Outcome.draw);
    final g = board(c, 2);
    expect(
      find.text(
        'Board 2, ${c.event!.player(g.white).name} – '
        '${c.event!.player(g.black).name}: ½–½, from beta.boylstonchess.org.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(board(c, 2).outcome, Outcome.unreported);
    // Taken back, so the next reading leaves it alone.
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(board(c, 2).outcome, Outcome.unreported);

    // Back on Pairings it is offered; then Stop ends the readings.
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    expect(find.text('Use ½–½'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-results-stop')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-results')), findsNothing);
  });
}

/// Pairs on this isolate, and only once [gate] opens, so a test can act
/// while pairings are being worked out.
class _Gated extends TournamentController {
  _Gated(super.repository);
  Completer<void>? gate;

  @override
  Future<PairingBatch> runProposal(
    Event snapshot,
    String? sectionId,
    bool onlyReady,
  ) async {
    await gate?.future;
    return proposeRounds(snapshot, sectionId, onlyReady);
  }
}
