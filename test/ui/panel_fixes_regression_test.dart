import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/infrastructure/roster_import.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/help_panel.dart';
import 'package:meow_chess/ui/new_section_panel.dart';
import 'package:meow_chess/ui/rating_refresh.dart';
import 'package:meow_chess/ui/rating_review_panel.dart';
import 'package:meow_chess/ui/select.dart';
import 'package:meow_chess/ui/side_game_panel.dart';
import 'package:meow_chess/ui/update_panels.dart';
import '../support.dart';

class _FailingRepository extends SqliteEventRepository {
  _FailingRepository() : super(':memory:');
  bool failWrites = false;

  @override
  Event commit(
    Event next, {
    required int expectedRevision,
    required String action,
  }) {
    if (failWrites) throw const TournamentException('Disk is full.');
    return super.commit(
      next,
      expectedRevision: expectedRevision,
      action: action,
    );
  }
}

Future<void> mount(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SizedBox(width: 420, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('help search matches every word in any order', () {
    final ratings = helpArticles.firstWhere((a) => a.id == 'ratings');
    expect(ratings.matches('expiration membership'), true);
    expect(ratings.matches('  supplement   USCF '), true);
    expect(ratings.matches('membership zebra'), false);
    expect(ratings.matches(''), true);
  });

  testWidgets('side-game players sort ignoring case and accents', (
    tester,
  ) async {
    final c = TournamentController(SqliteEventRepository(':memory:'))
      ..create('Club night');
    addTearDown(c.dispose);
    c.importPlayers([
      for (final (i, name) in [
        'Zhang Wei',
        'de la Cruz',
        'Ávila',
        'Brown',
      ].indexed)
        Player(id: 'p$i', name: name, rating: 1500),
    ]);
    await mount(
      tester,
      SideGamePanel(controller: c, onClose: () {}, onPaired: (_) {}),
    );
    final white = tester.widget<PlainSelect<String?>>(
      find.byKey(const ValueKey('side-game-white')),
    );
    expect(white.options.map((o) => o.label), [
      'Ávila',
      'Brown',
      'de la Cruz',
      'Zhang Wei',
    ]);
  });

  testWidgets('a successful website import clears an earlier error', (
    tester,
  ) async {
    final repository = _FailingRepository();
    final c = TournamentController(repository)..create('Ratings');
    addTearDown(c.dispose);
    c.importPlayers([Player(id: 'p', name: 'Existing', rating: 1000)]);
    await mount(
      tester,
      WebRosterPanel(
        controller: c,
        onClose: () {},
        loader: (_) async =>
            parseRoster('Name,USCF ID,Rating\nNew Player,99887766,1200'),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('roster-url')),
      'https://example.org/entries',
    );
    await tester.tap(find.text('Fetch updates'));
    await tester.pumpAndSettle();
    final confirm = find.text('Confirm 1 changes & save source');
    repository.failWrites = true;
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.textContaining('Disk is full'), findsOneWidget);
    repository.failWrites = false;
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.textContaining('changes applied'), findsOneWidget);
    expect(find.textContaining('Disk is full'), findsNothing);
  });

  testWidgets('the proposed rating uses the bundled code font weight', (
    tester,
  ) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final draft = RatingRefresh(
      c,
      lookup: (id) async => MemberObservation(
        id: id,
        name: 'Player',
        retrievedAt: '2026-10-03',
        supplementDate: '2026-10-01',
        ratings: const {'R': 1500},
      ),
    );
    addTearDown(draft.dispose);
    await tester.runAsync(() => draft.fetch());
    await mount(
      tester,
      PlayerRatingReview(
        draft: draft,
        player: c.event!.player('p0'),
        onBack: () {},
      ),
    );
    final text = tester.widget<Text>(find.text('2000 → 1500'));
    expect(text.style!.fontFamily, 'SourceCodePro');
    expect(text.style!.fontWeight ?? FontWeight.w400, FontWeight.w400);
  });

  group('new section', () {
    Future<List<List<String>>> open(
      WidgetTester tester,
      TournamentController c,
    ) async {
      final created = <List<String>>[];
      await mount(
        tester,
        NewSectionPanel(
          controller: c,
          ticked: const {},
          onCreated: created.add,
          onClose: () {},
        ),
      );
      return created;
    }

    Finder field(String key) => find.byKey(ValueKey('new-section-$key'));

    testWidgets('choosing who goes in is not a draft edit', (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      await open(tester, c);
      await tester.tap(find.byKey(const ValueKey('pool-everyone')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pool-none')));
      await tester.pumpAndSettle();
      expect(find.text('Draft saved · not applied'), findsNothing);
      expect(c.workspaceState.read('draft-new-section') ?? '', isEmpty);
      // A real choice is kept as a draft, and undoing it clears the draft.
      await tester.tap(find.text('Round robin'));
      await tester.pumpAndSettle();
      expect(find.text('Draft saved · not applied'), findsOneWidget);
      await tester.tap(find.text('Swiss'));
      await tester.pumpAndSettle();
      expect(find.text('Draft saved · not applied'), findsNothing);
    });

    testWidgets('round-robin rounds are checked against the field size', (
      tester,
    ) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final created = await open(tester, c);
      await tester.tap(find.byKey(const ValueKey('pool-everyone')));
      await tester.tap(find.text('Round robin'));
      await tester.pumpAndSettle();
      expect(find.text('4 players: 3 rounds'), findsOneWidget);
      await tester.enterText(field('name'), 'Club RR');
      await tester.enterText(field('rounds'), '5');
      await tester.pumpAndSettle();
      const problem = 'A round robin of 4 has 3 rounds. Enter 3 or fewer.';
      expect(find.text(problem), findsOneWidget);
      // Two games each still meet in the same rounds.
      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      expect(find.text(problem), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('create-section')));
      await tester.pumpAndSettle();
      expect(created, isEmpty);
      expect(c.event!.sections.where((s) => s.name == 'Club RR'), isEmpty);
      await tester.enterText(field('rounds'), '3');
      await tester.pumpAndSettle();
      expect(find.text(problem), findsNothing);
      await tester.tap(find.byKey(const ValueKey('create-section')));
      await tester.pumpAndSettle();
      final section = c.event!.sections.single;
      expect(created.single, [section.id]);
      expect(section.format, Format.roundRobin);
      expect(section.plannedRounds, 3);
      expect(section.doubleGames, true);
      expect(section.players, hasLength(4));
    });

    testWidgets('everyone not yet paired leaves their unpaired sections', (
      tester,
    ) async {
      final c = fixture(count: 8);
      addTearDown(c.dispose);
      expect(c.event!.sections, hasLength(2));
      final created = await open(tester, c);
      await tester.tap(find.byKey(const ValueKey('pool-everyone')));
      await tester.enterText(field('name'), 'Open');
      await tester.enterText(field('rounds'), '4');
      await tester.pumpAndSettle();
      expect(find.text('Create section with 8 players'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('create-section')));
      await tester.pumpAndSettle();
      final section = c.event!.sections.single;
      expect(created.single, [section.id]);
      expect(section.name, 'Open');
      expect(section.players, hasLength(8));
    });

    testWidgets('no one yet makes an empty section', (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final before = c.event!.sections.single;
      await open(tester, c);
      await tester.tap(find.byKey(const ValueKey('pool-none')));
      await tester.enterText(field('name'), 'Late entries');
      await tester.enterText(field('rounds'), '4');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create empty section'));
      await tester.pumpAndSettle();
      final added = c.event!.sections.last;
      expect(c.event!.sections, hasLength(2));
      expect(added.name, 'Late entries');
      expect(added.players, isEmpty);
      expect(c.event!.sections.first.players, before.players);
    });
  });
}
