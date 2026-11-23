// Before any result is in, the whole round can be paired again with one
// click from the Pairings page: it takes in whoever entered, left or asked
// for a bye since, says so when nothing moved, and Undo puts it back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';
import 'dock_host.dart';

Future<void> mount(
  WidgetTester tester,
  TournamentController c, {
  String? sectionId,
  void Function(String, Round)? onRepaired,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Scaffold(
        body: DockHost(
          child: ListenableBuilder(
            listenable: c,
            builder: (_, _) => ResultsView(
              controller: c,
              sectionId: sectionId,
              onRepaired: onRepaired,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Eight players in one Swiss section with round 1 posted. The widget tests
/// run on a fake clock, so the engine runs here instead of on an isolate.
Future<TournamentController> firstRound(
  WidgetTester tester, {
  bool fide = false,
}) async {
  final c = _Direct(SqliteEventRepository(':memory:'));
  addTearDown(c.dispose);
  c.create('Club Open');
  c.importPlayers([
    for (var i = 0; i < 8; i++)
      Player(id: 'p$i', name: 'Player $i', rating: 2000 - i * 50),
  ]);
  c.addSection('Open', Format.swiss, 4);
  if (fide) {
    c.change(
      'FIDE rated',
      c.event!.copy(
        sections: [for (final s in c.event!.sections) s.copy(fideRated: true)],
      ),
    );
  }
  c.post(await c.propose());
  return c;
}

class _Direct extends TournamentController {
  _Direct(super.repository);
  @override
  Future<PairingBatch> runProposal(
    Event snapshot,
    String? sectionId,
    bool onlyReady,
  ) async => proposeRounds(snapshot, sectionId, onlyReady);
}

Round last(TournamentController c) => c.event!.sections.single.rounds.last;
Set<String> seated(Round r) => {
  for (final g in r.games) ...[g.white, g.black],
};

/// Opens the Change pairings menu, where Re-pair round and Flip pairing are.
Future<void> openChange(WidgetTester tester) async {
  if (find.byKey(const ValueKey('edit-pairings')).evaluate().isNotEmpty) return;
  await tester.tap(find.byKey(const ValueKey('change-pairings')));
  await tester.pumpAndSettle();
}

/// Chooses [item] from the Change pairings menu.
Future<void> choose(WidgetTester tester, Finder item) async {
  await openChange(tester);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

void main() {
  final again = find.byKey(const ValueKey('repair-round'));

  testWidgets('one click pairs the round again with a late entry, and Undo '
      'puts the first pairings back', (tester) async {
    final c = await firstRound(tester);
    final section = c.event!.sections.single;
    final before = last(c);
    final notified = <(String, int)>[];
    await mount(
      tester,
      c,
      sectionId: section.id,
      onRepaired: (id, round) => notified.add((id, round.number)),
    );
    // Beside Edit pairings in the Change pairings menu.
    await openChange(tester);
    expect(find.byKey(const ValueKey('edit-pairings')), findsOneWidget);
    expect(tester.widget<MenuItemButton>(again).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('change-pairings')));
    await tester.pumpAndSettle();

    // Two walk-ups after the pairings went up.
    c.importPlayers([
      Player(id: 'late1', name: 'Late One', rating: 1900),
      Player(id: 'late2', name: 'Late Two', rating: 1500),
    ]);
    c.movePlayers(['late1', 'late2'], section.id);
    await tester.pumpAndSettle();
    // Entered once the round was up, each has a bye for it.
    expect(seated(last(c)), isNot(contains('late1')));
    expect(c.event!.player('late1').byes, contains(1));

    await choose(tester, again);
    expect(find.byType(Dialog), findsNothing);
    final round = last(c);
    expect(round.number, 1);
    expect(round.games, hasLength(5));
    expect(seated(round), containsAll(['late1', 'late2']));
    expect(c.event!.player('late1').byes, isNot(contains(1)));
    expect(round.byes, isEmpty);
    expect(round.revision, before.revision + 1);
    // New games: a box left open on an old board cannot write to them.
    expect(
      round.games
          .map((g) => g.id)
          .toSet()
          .intersection(before.games.map((g) => g.id).toSet()),
      isEmpty,
    );
    expect(c.event!.sections.single.rounds, hasLength(1));
    expect(c.graph.nodes[c.graph.head]!.action, 'Re-pair round 1');
    expect(notified, [(section.id, 1)]);
    expect(
      find.text(
        'Round 1 paired again. Late One and Late Two are paired instead of '
        'taking a late-entry bye.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(last(c).games.map((g) => g.id), before.games.map((g) => g.id));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with nothing changed the pairings stay, the notice says so, '
      'and no step is saved for Undo to take back', (tester) async {
    final c = await firstRound(tester);
    final before = last(c);
    final head = c.graph.head, revision = c.event!.revision;
    final steps = c.graph.nodes.length;
    final notified = <String>[];
    await mount(
      tester,
      c,
      sectionId: c.event!.sections.single.id,
      onRepaired: (id, _) => notified.add(id),
    );
    // Pressed over and over, as a TD does when nothing seems to happen.
    for (var i = 0; i < 3; i++) {
      await choose(tester, again);
    }
    // The very same round: its games, their IDs and when it was posted.
    expect(last(c).toJson(), before.toJson());
    expect(c.event!.revision, revision);
    expect(c.graph.head, head);
    expect(c.graph.nodes, hasLength(steps));
    expect(notified, isEmpty);
    expect(
      find.text(
        'Round 1 pairings stay as they are: nothing has changed since it '
        'was paired.',
      ),
      findsOneWidget,
    );
    // Nothing was saved, so the notice offers no Undo: it would take back
    // the pairings themselves.
    expect(find.text('Undo'), findsNothing);
    // One Undo from here takes the pairings back.
    c.undo();
    expect(c.event!.sections.single.rounds, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a withdrawal and a bye asked for since are honoured', (
    tester,
  ) async {
    final c = await firstRound(tester);
    final section = c.event!.sections.single;
    await mount(tester, c, sectionId: section.id);
    c.setWithdrawn(['p7'], true);
    c.change(
      'Bye asked for',
      c.event!.copy(
        players: [
          for (final p in c.event!.players)
            p.id == 'p6' ? p.copy(byes: {1: 1}) : p,
        ],
      ),
    );
    await tester.pumpAndSettle();
    await choose(tester, again);
    final round = last(c);
    expect(round.games, hasLength(3));
    expect(seated(round), isNot(contains('p7')));
    expect(seated(round), isNot(contains('p6')));
    expect(round.byes.map((b) => b.player), contains('p6'));
    expect(find.text('Round 1 paired again.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('it is offered only before the round has a result, for the '
      'section on screen', (tester) async {
    final c = await firstRound(tester);
    final section = c.event!.sections.single;
    // All sections: no single round to pair again.
    await mount(tester, c);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('change-pairings')))
          .onPressed,
      isNull,
    );
    await mount(tester, c, sectionId: section.id);
    await openChange(tester);
    expect(tester.widget<MenuItemButton>(again).onPressed, isNotNull);
    // One result in: only the boards not started can be paired again. The
    // menu keeps its items, greyed, so nothing moves.
    c.recordResult(last(c).games.first.id, Outcome.draw);
    await tester.pumpAndSettle();
    await openChange(tester);
    expect(tester.widget<MenuItemButton>(again).onPressed, isNull);
    expect(find.byKey(const ValueKey('repair-unstarted')), findsOneWidget);
    await expectLater(
      c.repairRound(section.id),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('Round 1 has started'),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a FIDE section, which has no selective re-pairing, can pair '
      'its round again and settles its pairing numbers again', (tester) async {
    final c = await firstRound(tester, fide: true);
    final section = c.event!.sections.single;
    expect(section.fideOrder, isNot(contains('late')));
    await mount(tester, c, sectionId: section.id);
    await openChange(tester);
    expect(find.byKey(const ValueKey('repair-unstarted')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('change-pairings')));
    await tester.pumpAndSettle();
    c.importPlayers([Player(id: 'late', name: 'Late Entry', rating: 2100)]);
    c.movePlayers(['late'], section.id);
    await tester.pumpAndSettle();
    await choose(tester, again);
    final after = c.event!.sections.single;
    expect(after.rounds, hasLength(1));
    // The strongest player takes pairing number 1.
    expect(after.fideOrder.first, 'late');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Flip pairing pairs round 1 again with the coin toss reversed, '
      'for USCF and FIDE sections alike, and Undo puts it back', (
    tester,
  ) async {
    for (final fide in [false, true]) {
      final c = await firstRound(tester, fide: fide);
      final section = c.event!.sections.single;
      final before = last(c);
      final toss = c.event!.colorToss;
      await mount(tester, c, sectionId: section.id);
      final flip = find.byKey(const ValueKey('flip-pairing'));
      await openChange(tester);
      expect(flip, findsOneWidget);
      await choose(tester, flip);
      final after = last(c);
      Set<String> boards(Round r) => {
        for (final g in r.games) '${g.board}:${g.white}-${g.black}',
      };
      Set<String> swapped(Round r) => {
        for (final g in r.games) '${g.board}:${g.black}-${g.white}',
      };
      expect(boards(after), swapped(before), reason: 'fide: $fide');
      expect(c.event!.colorToss, isNot(toss));
      final top = after.games.firstWhere((g) => g.board == 1);
      expect(
        find.text(
          'Round 1 pairing flipped. '
          '${c.event!.player(top.white).name} has white on board 1.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(boards(last(c)), boards(before));
      expect(c.event!.colorToss, toss);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Flip pairing is offered for round 1 only', (tester) async {
    final c = await firstRound(tester);
    final section = c.event!.sections.single;
    for (final g in last(c).games) {
      c.recordResult(g.id, Outcome.draw);
    }
    c.post(await c.propose());
    await mount(tester, c, sectionId: section.id);
    await openChange(tester);
    expect(again, findsOneWidget);
    expect(find.byKey(const ValueKey('flip-pairing')), findsNothing);
    await expectLater(
      c.repairRound(section.id, flipColors: true),
      throwsA(isA<TournamentException>()),
    );
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'Flip pairing flips round 1 in every section, as one coin toss',
    () async {
      final c = fixture(count: 8, format: Format.swiss);
      addTearDown(c.dispose);
      c.post(await c.propose());
      final [q1, q2] = c.event!.sections;
      String seats(Round r) => [
        for (final g in r.games) '${g.board}:${g.white}-${g.black}',
      ].join(',');
      String flipped(Round r) => [
        for (final g in r.games) '${g.board}:${g.black}-${g.white}',
      ].join(',');
      final before = flipped(q2.rounds.single);
      await c.repairRound(q1.id, flipColors: true);
      expect(seats(c.event!.sections[1].rounds.single), before);

      // Once another section has started, the toss cannot change.
      final game = c.event!.sections[1].rounds.single.games.first;
      c.recordResult(game.id, Outcome.draw);
      await expectLater(
        c.repairRound(q1.id, flipColors: true),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'message',
            contains(q2.name),
          ),
        ),
      );
    },
  );
}
