import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/domain/pairing.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../support.dart';

Future<void> mount(
  WidgetTester tester,
  TournamentController c, {
  Size size = const Size(1400, 900),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
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

void main() {
  for (final (size, scale) in [
    (const Size(960, 600), 1.0),
    (const Size(1280, 720), 2.0),
  ]) {
    testWidgets('quad editor fits at $size with $scale text', (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      await mount(tester, c, size: size, scale: scale);
      await tester.tap(find.byKey(const ValueKey('edit-quad-pairings')));
      await tester.pumpAndSettle();
      final flip = find.byKey(const ValueKey('quad-flip-0-0'));
      await tester.ensureVisible(flip);
      await tester.tap(flip);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-quad-pairings')));
      await tester.pumpAndSettle();
      expect(c.event!.sections.single.quadPairings, isNotEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'All sections exposes editor; flip saves only chosen quad and undo works',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final first = c.event!.sections.first, other = c.event!.sections.last;
      await mount(tester, c);
      await tester.tap(find.byKey(const ValueKey('edit-quad-pairings')));
      await tester.pumpAndSettle();
      expect(find.text('Edit quad pairings'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('quad-flip-0-0')));
      await tester.pump();
      // Edits are a draft until saved.
      expect(
        c.event!.sections.first.rounds.first.games.first.white,
        first.rounds.first.games.first.white,
      );
      await tester.tap(find.byKey(const ValueKey('save-quad-pairings')));
      await tester.pumpAndSettle();
      expect(
        c.event!.sections.first.rounds.first.games.first.white,
        first.rounds.first.games.first.black,
      );
      expect(c.event!.sections.last.toJson(), other.toJson());
      await tester.tap(find.byKey(const ValueKey('undo')));
      await tester.pumpAndSettle();
      expect(c.event!.sections.first.toJson(), first.toJson());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('opponent changes show repeat error; cancel discards draft', (
    tester,
  ) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final s = c.event!.sections.single;
    final pairs = sectionSchedule(s).first;
    await mount(tester, c);
    await tester.tap(find.byKey(const ValueKey('edit-quad-pairings')));
    await tester.pumpAndSettle();
    final seat = find.byKey(ValueKey(('quad-seat', 0, 0, pairs[0].$1!)));
    await tester.ensureVisible(seat);
    await tester.tap(seat);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, c.event!.player(pairs[1].$1!).name),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-quad-pairings')));
    await tester.pumpAndSettle();
    expect(find.textContaining('repeats'), findsOneWidget);
    expect(c.event!.sections.single.quadPairings, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.event!.sections.single.toJson(), s.toJson());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('results lock their round; future colors can still be changed', (
    tester,
  ) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    c.post((await tester.runAsync(() => c.propose()))!);
    final first = c.event!.sections.single.rounds.first;
    c.recordResult(first.games.first.id, Outcome.draw);
    await mount(tester, c);
    await tester.tap(find.byKey(const ValueKey('edit-quad-pairings')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('quad-flip-0-0')))
          .onPressed,
      isNull,
    );
    final flip = find.byKey(const ValueKey('quad-flip-1-0'));
    await tester.ensureVisible(flip);
    await tester.tap(flip);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-quad-pairings')));
    await tester.pumpAndSettle();
    expect(
      c.event!.sections.single.rounds.first.games.first.outcome,
      Outcome.draw,
    );
    expect(c.event!.sections.single.quadPairings, isNotEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
