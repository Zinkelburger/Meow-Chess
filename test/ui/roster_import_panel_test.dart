import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/ui/roster_import_panel.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';

Finder mapping(String field) => find.byWidgetPredicate(
  (w) =>
      w is DropdownButtonFormField<int> &&
      w.key.toString().contains('mapping-$field-'),
);

Future<void> choose(WidgetTester tester, Finder field, String option) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('narrow review panel remains usable with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: RosterImportPanel(
            controller: c,
            source: 'Name,Rating,ID\nAda,1500,00123456',
            filename: 'roster.csv',
            onClose: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(mapping('name'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('confirm-roster-import')));
    await tester.pumpAndSettle();
    expect(c.event!.players.last.name, 'Ada');
    expect(tester.takeException(), isNull);
  });

  testWidgets('review custom columns, import exactly the preview, then undo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final before = c.event!.revision;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: meowTheme(Brightness.light),
        home: Scaffold(
          body: RosterImportPanel(
            controller: c,
            source: 'Registrant;Seed;Member\n"Lee; Morgan";1600;00123456',
            filename: 'members.csv',
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    // Settings and preview never change the event.
    await choose(
      tester,
      find.byKey(const ValueKey('import-delimiter')),
      'Semicolon',
    );
    await tester.tap(find.byKey(const ValueKey('import-header')));
    await tester.pumpAndSettle();
    await choose(tester, mapping('name'), '1: Registrant');
    await choose(tester, mapping('rating'), '2: Seed');
    await choose(tester, mapping('memberId'), '3: Member');
    expect(c.event!.revision, before);
    await tester.tap(find.byKey(const ValueKey('confirm-roster-import')));
    await tester.pumpAndSettle();
    expect(closed, false);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Imported 1 players'), findsOneWidget);
    await tester.tap(find.text('Done'));
    expect(closed, true);
    expect(c.event!.players.last.name, 'Lee; Morgan');
    expect(c.event!.players.last.rating, 1600);
    expect(c.event!.players.last.memberId, '00123456');
    c.undo();
    await tester.pumpAndSettle();
    expect(c.event!.players.length, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invalid rows require an explicit skip and cancel makes no changes',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RosterImportPanel(
              controller: c,
              source: 'Name,Rating\nAda,1500\nBo,bad',
              filename: 'roster.csv',
              onClose: () => cancelled = true,
            ),
          ),
        ),
      );
      final button = find.byKey(const ValueKey('confirm-roster-import'));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      final skip = find.byKey(const ValueKey('import-skip-invalid'));
      await tester.ensureVisible(skip);
      await tester.pumpAndSettle();
      await tester.tap(skip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(find.text('Cancel'));
      expect(cancelled, true);
      expect(c.event!.players.length, 4);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom separator errors recover and duplicate mappings are blocked',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RosterImportPanel(
              controller: c,
              source: 'Name~Rating\nAda~1500',
              filename: 'roster.txt',
              onClose: () {},
            ),
          ),
        ),
      );
      await choose(
        tester,
        find.byKey(const ValueKey('import-delimiter')),
        'Custom',
      );
      expect(
        find.text('Enter one separator character, such as |.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('import-custom-delimiter')),
        '~',
      );
      await tester.pumpAndSettle();
      expect(find.text('Import 1 player'), findsOneWidget);
      await choose(tester, mapping('rating'), '1: Name');
      expect(
        find.text('Each file column can be used only once.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('confirm-roster-import')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
