import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/ui/roster_import_panel.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';

/// Opens the import window over a blank screen; [result] gets its summary.
Future<List<String?>> open(
  WidgetTester tester,
  TournamentController c,
  String source, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  final result = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: meowTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result.add(
              await showRosterImport(
                context,
                controller: c,
                source: source,
                filename: 'roster.csv',
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return result;
}

Finder column(int i) => find.byKey(ValueKey('map-column-$i'));
Finder get importButton => find.byKey(const ValueKey('confirm-roster-import'));
bool enabled(WidgetTester tester) =>
    tester.widget<FilledButton>(importButton).onPressed != null;
String summary(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('import-summary'))).data!;

void main() {
  testWidgets('small window with large text stays usable', (tester) async {
    tester.view.physicalSize = const Size(960, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final result = await open(
      tester,
      c,
      'Name,Rating,ID\nAda,1500,00123456',
      brightness: Brightness.dark,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(importButton);
    await tester.pumpAndSettle();
    expect(result.single, 'Imported 1 players');
    expect(c.event!.players.last.name, 'Ada');
    expect(c.event!.players.last.memberId, '00123456');
    expect(tester.takeException(), isNull);
  });

  testWidgets('detects the separator, maps columns, imports, then undoes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final before = c.event!.revision;
    final result = await open(
      tester,
      c,
      'Registrant;Seed;Member\n"Lee; Morgan";1600;00123456',
    );
    // A semicolon inside quotes stays in the name.
    expect(find.text('Detected semicolon'), findsOneWidget);
    expect(find.text('Lee; Morgan'), findsOneWidget);
    // Unknown headings read as a player until the TD says otherwise.
    await tester.tap(find.byKey(const ValueKey('import-header')));
    await tester.pumpAndSettle();
    expect(summary(tester), 'Choose the column that holds player names');
    expect(enabled(tester), false);
    await chooseOption(tester, column(0), 'Name');
    await chooseOption(tester, column(1), 'Rating');
    await chooseOption(tester, column(2), 'US Chess ID');
    expect(summary(tester), '1 new player');
    expect(c.event!.revision, before);
    await tester.tap(importButton);
    await tester.pumpAndSettle();
    expect(result.single, 'Imported 1 players');
    expect(find.byType(Dialog), findsNothing);
    expect(c.event!.players.last.name, 'Lee; Morgan');
    expect(c.event!.players.last.rating, 1600);
    expect(c.event!.players.last.memberId, '00123456');
    c.undo();
    expect(c.event!.players.length, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid rows need an explicit skip; Cancel changes nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final result = await open(tester, c, 'Name,Rating\nAda,1500\nBo,bad');
    expect(summary(tester), '1 new player · 1 row needs attention');
    expect(enabled(tester), false);
    // The problem is shown on its row.
    expect(find.textContaining('Rating must be'), findsOneWidget);
    await tester.tap(find.text('Need attention 1'));
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('import-skip-invalid')));
    await tester.pump();
    expect(enabled(tester), true);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result.single, isNull);
    expect(c.event!.players.length, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('any typed separator, and repeated spaces as one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    await open(tester, c, 'Name~Rating\nAda~1500');
    // Nothing recognisable: one column, read as names.
    expect(find.text('Ada~1500'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('import-other-separator')),
      '~',
    );
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Import 1 player'), findsOneWidget);
    // A field belongs to one column: choosing it again moves it.
    await chooseOption(tester, column(1), 'Name');
    expect(
      find.descendant(of: column(0), matching: find.text('Don’t import')),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await open(tester, c, 'Name   Rating\nAda    1500\nBo  1400');
    await tester.tap(find.byKey(const ValueKey('separator-comma')));
    await tester.tap(find.byKey(const ValueKey('separator-space')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('import-merge')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('import-header')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('import-header')));
    await tester.pumpAndSettle();
    expect(find.text('1400'), findsOneWidget);
    expect(summary(tester), '2 new players');
    expect(tester.takeException(), isNull);
  });

  testWidgets('players already in the event are marked and skipped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final existing = c.event!.players.first;
    await open(
      tester,
      c,
      'Name,ID,Rating\n${existing.name},${existing.memberId},1500\nNew Kid,,900',
    );
    expect(find.text('Already in the event'), findsOneWidget);
    expect(summary(tester), '1 new player · 1 already in the event');
    expect(find.text('Import 1 player'), findsOneWidget);
  });
}
