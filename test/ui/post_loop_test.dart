import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/failures.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/dialogs.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../support.dart';

void finishAll(TournamentController c) {
  for (final s in c.event!.sections) {
    for (final g in s.rounds.lastOrNull?.games ?? const <Game>[]) {
      if (!g.outcome.resolved) c.recordResult(g.id, Outcome.draw);
    }
  }
}

Future<void> mount(WidgetTester tester, TournamentController c) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      home: Workspace(
        controller: c,
        path: ':memory:',
        onClose: () {},
        onTheme: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> post(WidgetTester tester, TournamentController c) async {
  await tester.tap(find.text('Pairings').first);
  await tester.pumpAndSettle();
  final before = c.event!.revision;
  await tester.tap(find.byKey(const ValueKey('pair-next-round')));
  await tester.runAsync(() async {
    for (var i = 0; i < 200 && c.event!.revision == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  test('the post button names the round and says why it is held', () async {
    final c = fixture();
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    expect(
      postState(c.event!, null).label,
      'Create pairings · Round 1 · 2 sections',
    );
    expect(postState(c.event!, q1).label, 'Create pairings · Round 1');
    c.post(await c.propose());
    // One section's results are in, the other's are not.
    for (final g in c.event!.sections.first.rounds.last.games) {
      c.recordResult(g.id, Outcome.whiteWin);
    }
    final both = postState(c.event!, null);
    expect(both.label, 'Create pairings · Round 2 · 1 section');
    expect(both.why, '${q2.name} waits for 2 results.');
    final held = postState(c.event!, c.event!.sections.last);
    expect(held.label, isNull);
    expect(held.why, 'Enter 2 results first.');
    for (var round = 1; round < q1.plannedRounds; round++) {
      finishAll(c);
      c.post(await c.propose());
    }
    expect(postState(c.event!, null).why, contains('still to enter'));
    finishAll(c);
    expect(postState(c.event!, null).complete, true);
  });

  testWidgets(
    'creating pairings from one section creates every ready section once',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      await mount(tester, c);
      final first = c.event!.sections.first.id;
      await tester.tap(find.byKey(ValueKey('section-chip-$first')));
      await tester.pumpAndSettle();
      await post(tester, c);
      expect(c.event!.sections.map((s) => s.rounds.length), [1, 1]);
      expect(find.byKey(const ValueKey('pair-next-round')), findsNothing);
      expect(find.byKey(const ValueKey('post-notes')), findsNothing);
      final waitingRevision = c.event!.sections.last.rounds.single.revision;
      for (final g in c.event!.sections.first.rounds.single.games) {
        c.recordResult(g.id, Outcome.draw);
      }
      await tester.pump();
      await post(tester, c);
      expect(c.event!.sections.map((s) => s.rounds.length), [2, 1]);
      expect(c.event!.sections.last.rounds.single.revision, waitingRevision);
      expect(find.byKey(const ValueKey('post-notes')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('event complete replaces the post button', (tester) async {
    final c = fixture();
    addTearDown(c.dispose);
    for (
      var round = 0;
      round < c.event!.sections.first.plannedRounds;
      round++
    ) {
      c.post((await tester.runAsync(() => c.propose()))!);
      finishAll(c);
    }
    await mount(tester, c);
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pair-next-round')), findsNothing);
    expect(find.byKey(const ValueKey('event-complete')), findsOneWidget);
    await tester.tap(find.text('Finish & export'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-scope')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Swiss rounds post without a certification notice', (
    tester,
  ) async {
    final c = TournamentController(SqliteEventRepository(':memory:'))
      ..create('Tuesday Swiss');
    addTearDown(c.dispose);
    c.importPlayers([
      for (var i = 0; i < 6; i++)
        Player(id: 's$i', name: 'Swiss $i', rating: 1800 - i * 50),
    ]);
    c.addSection('Open', Format.swiss, 3);
    await mount(tester, c);
    await post(tester, c);
    expect(c.event!.sections.single.rounds, hasLength(1));
    expect(find.textContaining('not yet certified'), findsNothing);
    expect(find.byKey(const ValueKey('post-notes')), findsNothing);
    finishAll(c);
    await tester.pump();
    await post(tester, c);
    expect(c.event!.sections.single.rounds, hasLength(2));
    expect(find.textContaining('not yet certified'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('errors stay until closed and read as plain sentences', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFailure(
                context,
                const FileSystemException(
                  'Cannot open file',
                  '/media/usb/event.meow',
                  OSError('No such file or directory', 2),
                ),
              ),
              child: const Text('Fail'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fail'));
    await tester.pump();
    const message =
        'Cannot open file: /media/usb/event.meow (No such file or directory).';
    expect(find.text(message), findsOneWidget);
    await tester.pump(const Duration(minutes: 2));
    expect(find.text(message), findsOneWidget);
    expect(find.textContaining('FileSystemException'), findsNothing);
  });

  test('plain messages drop exception class names', () {
    expect(
      plainMessage(const TournamentException('Board 3 is taken.')),
      'Board 3 is taken.',
    );
    expect(
      plainMessage(Exception('database is locked')),
      'Another program has this event file open. Close it there, then try again.',
    );
    expect(plainMessage(StateError('no event loaded')), 'No event loaded.');
    expect(plainMessage(Exception('boom')), 'Something went wrong: boom.');
  });
}
