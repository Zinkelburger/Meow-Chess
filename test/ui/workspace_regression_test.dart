import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/remembered_printing.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/event_panel.dart';
import 'package:meow_chess/ui/history_panel.dart';
import 'package:meow_chess/ui/new_section_panel.dart';
import 'package:meow_chess/ui/panels.dart';
import 'package:meow_chess/ui/player_panel.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';

import '../support.dart';

Future<void> mount(WidgetTester tester, TournamentController c) async {
  tester.view.physicalSize = const Size(1400, 1000);
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

Future<void> postRound(
  WidgetTester tester,
  TournamentController c, {
  String? sectionId,
}) async {
  c.post((await tester.runAsync(() => c.propose(sectionId: sectionId)))!);
}

Future<void> chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<void> sectionMenu(
  WidgetTester tester,
  String sectionId,
  String item,
) async {
  await tester.tap(find.byKey(ValueKey('section-chip-$sectionId')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(ValueKey('section-chip-$sectionId')),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

Finder box(String id) => find.descendant(
  of: find.byKey(ValueKey('player-$id')),
  matching: find.byType(PlainCheckbox),
);

class _Platform extends PrintingPlatform {
  @override
  Future<PrintingInfo> info() async => const PrintingInfo(canPrint: true);

  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A file whose folder refused SQLite's recovery file.
class _Unprotected extends SqliteEventRepository {
  _Unprotected() : super(':memory:');
  @override
  bool get crashProtected => false;
}

class _MemoryPreference extends PrinterPreference {
  Printer? saved;
  @override
  Future<Printer?> read() async => saved;
  @override
  Future<void> write(Printer printer) async => saved = printer;
}

void main() {
  group('docked panels follow the event', () {
    testWidgets('Backups offers Back up now once a folder is set', (
      tester,
    ) async {
      final c = fixture();
      addTearDown(c.dispose);
      await mount(tester, c);
      await tester.tap(find.byKey(const ValueKey('status-backup')));
      await tester.pumpAndSettle();
      expect(find.text('None chosen.'), findsOneWidget);
      expect(find.text('Back up now'), findsNothing);
      // The native picker cannot be driven; set the folder as it would.
      c.change(
        'Choose backup folder',
        c.event!.copy(backupFolder: '/media/usb'),
      );
      await tester.pumpAndSettle();
      expect(find.text('None chosen.'), findsNothing);
      expect(find.text('Back up now'), findsOneWidget);
      expect(find.text('Stop backups'), findsOneWidget);
    });

    testWidgets('Lookup shows the score after a result is entered', (
      tester,
    ) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      await postRound(tester, c);
      await mount(tester, c);
      final game = c.event!.sections.first.rounds.last.games.first;
      final white = c.event!.player(game.white);
      await chord(tester, LogicalKeyboardKey.keyL);
      await tester.enterText(
        find.byKey(const ValueKey('lookup-query')),
        white.name,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Score 0'), findsOneWidget);
      c.recordResult(game.id, Outcome.whiteWin);
      await tester.pumpAndSettle();
      expect(find.textContaining('Score 1'), findsOneWidget);
      expect(find.textContaining('Score 0'), findsNothing);
    });

    testWidgets('Combine after Undo moves only the live roster', (
      tester,
    ) async {
      final c = fixture(count: 12);
      addTearDown(c.dispose);
      final [q1, q2, q3] = c.event!.sections;
      final visitor = q3.players.first;
      await mount(tester, c);
      c.movePlayers([visitor], q1.id);
      await tester.pumpAndSettle();
      await sectionMenu(tester, q1.id, 'Combine sections…');
      // The move is undone with the panel open.
      await tester.tap(find.byKey(const ValueKey('undo')));
      await tester.pumpAndSettle();
      expect(c.event!.sectionOf(visitor)?.id, q3.id);
      await tester.tap(find.byKey(ValueKey('combine-into-${q2.id}')));
      await tester.pump();
      await tester.tap(find.text('Combine'));
      await tester.pumpAndSettle();
      final sections = {for (final s in c.event!.sections) s.id: s};
      expect(sections[q1.id]!.players, isEmpty);
      expect(sections[q2.id]!.players, hasLength(8));
      expect(sections[q3.id]!.players, q3.players);
    });

    testWidgets('section settings lock the format once rounds are posted', (
      tester,
    ) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      final q1 = c.event!.sections.first;
      await mount(tester, c);
      await sectionMenu(tester, q1.id, 'Rename / section settings…');
      // Before round 1 the format is a choice; after, it is stated with a
      // lock, never a greyed control.
      expect(find.byKey(const ValueKey('field-format')), findsOneWidget);
      expect(find.text('Set before round 1'), findsNothing);
      await postRound(tester, c, sectionId: q1.id);
      c.change(
        'Rename',
        c.event!.copy(
          sections: [
            for (final s in c.event!.sections)
              s.id == q1.id ? s.copy(name: 'Top') : s,
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('field-format')), findsNothing);
      expect(find.byKey(const ValueKey('field-format-locked')), findsOneWidget);
      expect(find.text('Set before round 1'), findsWidgets);
      expect(find.text('Top settings'), findsOneWidget);
    });
  });

  group('keyboard', () {
    testWidgets('Ctrl+Z undoes typing in a field, and the event outside it', (
      tester,
    ) async {
      final c = fixture();
      addTearDown(c.dispose);
      c.change('Rename event', c.event!.copy(name: 'Renamed'));
      await mount(tester, c);
      final search = find.descendant(
        of: find.byKey(const ValueKey('player-search')),
        matching: find.byType(EditableText),
      );
      await tester.tap(search);
      await tester.pump();
      await tester.enterText(search, 'Player');
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(search, 'Player 0');
      await tester.pump(const Duration(seconds: 1));
      await chord(tester, LogicalKeyboardKey.keyZ);
      expect(tester.widget<EditableText>(search).controller.text, 'Player');
      expect(c.event!.name, 'Renamed');
      // Ctrl+H in a field does not open History.
      await chord(tester, LogicalKeyboardKey.keyH);
      expect(find.byType(HistoryPanel), findsNothing);
      // Focus a row, outside any field.
      Focus.of(tester.element(find.text('Player 00'))).requestFocus();
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.keyZ);
      expect(c.event!.name, 'Saturday Quads');
      await chord(tester, LogicalKeyboardKey.keyH);
      expect(find.byType(HistoryPanel), findsOneWidget);
    });

    testWidgets('a Mac uses Command for workspace shortcuts', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final c = fixture();
        addTearDown(c.dispose);
        c.change('Rename event', c.event!.copy(name: 'Renamed'));
        await mount(tester, c);
        await chord(tester, LogicalKeyboardKey.keyZ);
        expect(c.event!.name, 'Renamed');
        await chord(
          tester,
          LogicalKeyboardKey.keyZ,
          modifier: LogicalKeyboardKey.metaLeft,
        );
        expect(c.event!.name, 'Saturday Quads');
        await chord(
          tester,
          LogicalKeyboardKey.keyZ,
          modifier: LogicalKeyboardKey.metaLeft,
          shift: true,
        );
        expect(c.event!.name, 'Renamed');
        // ⌘H hides the app on a Mac, so History is ⌘Y.
        await chord(
          tester,
          LogicalKeyboardKey.keyY,
          modifier: LogicalKeyboardKey.metaLeft,
        );
        expect(find.byType(HistoryPanel), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await tester.pumpAndSettle();
        expect(find.text('⌘Z — Undo'), findsOneWidget);
        expect(find.text('⌘⇧Z — Redo'), findsOneWidget);
        expect(find.textContaining('Ctrl'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Backspace on a focused row removes the player', (
      tester,
    ) async {
      final c = fixture();
      addTearDown(c.dispose);
      await mount(tester, c);
      final id = c.event!.sections.first.players.last;
      Focus.of(
        tester.element(find.text(c.event!.player(id).name)),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(c.event!.players.any((p) => p.id == id), false);
    });
  });

  group('printing', () {
    test('Ctrl+P prints every section on Export, and a removed one as all', () {
      final c = fixture();
      addTearDown(c.dispose);
      final id = c.event!.sections.first.id;
      expect(printScope(c.event!, TaskView.reports, id), (
        kind: ReportKind.packet,
        sectionId: null,
      ));
      expect(printScope(c.event!, TaskView.players, id), (
        kind: ReportKind.sections,
        sectionId: id,
      ));
      expect(printScope(c.event!, TaskView.results, 'gone'), (
        kind: ReportKind.packet,
        sectionId: null,
      ));
    });

    testWidgets('Ctrl+P on Pairings still prints after Undo removes the '
        'chosen section', (tester) async {
      final previous = PrintingPlatform.instance;
      PrintingPlatform.instance = _Platform();
      addTearDown(() => PrintingPlatform.instance = previous);
      final c = fixture();
      addTearDown(c.dispose);
      c.change(
        'Add section',
        c.event!.copy(
          sections: [
            ...c.event!.sections,
            Section(id: 'extra', name: 'Extra', players: const []),
          ],
        ),
      );
      await mount(tester, c);
      await tester.tap(find.byKey(const ValueKey('section-chip-extra')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pairings').first);
      await tester.pumpAndSettle();
      c.undo();
      await tester.pumpAndSettle();
      await chord(tester, LogicalKeyboardKey.keyP);
      expect(find.byKey(const ValueKey('print-panel')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the first print chooses a printer in the panel', (
      tester,
    ) async {
      final previous = PrintingPlatform.instance;
      PrintingPlatform.instance = _Platform();
      addTearDown(() => PrintingPlatform.instance = previous);
      const a = Printer(url: 'a', name: 'Club printer', isDefault: true);
      const b = Printer(url: 'b', name: 'Office printer');
      final sent = <String?>[];
      final printing = RememberedPrinting(
        preference: _MemoryPreference(),
        info: () async => const PrintingInfo(
          canPrint: true,
          directPrint: true,
          canListPrinters: true,
        ),
        printers: () async => [a, b],
        send: (printer, _, _) async {
          sent.add(printer?.url);
          return true;
        },
      );
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrintPanel(
              event: c.event!,
              controller: c,
              kind: ReportKind.packet,
              onClose: () {},
              printing: printing,
              printNow: true,
              generate: (_) async => Uint8List.fromList([1, 2, 3]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Opened to print: the choice is in the panel, never a dialog.
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(const ValueKey('print-printer')), findsOneWidget);
      expect(sent, isEmpty);
      await chooseOption(
        tester,
        find.byKey(const ValueKey('print-printer')),
        'Office printer',
      );
      await tester.tap(find.byKey(const ValueKey('print-to-printer')));
      await tester.pumpAndSettle();
      expect(sent, ['b']);
      expect(find.byKey(const ValueKey('print-printer')), findsNothing);
      // The next print goes straight to the remembered printer.
      await tester.tap(find.byKey(const ValueKey('print-preview')));
      await tester.pumpAndSettle();
      expect(sent, ['b', 'b']);
      // Choose printer… asks again; Cancel sends nothing.
      await tester.tap(find.text('Choose printer…'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('print-cancel-printer')));
      await tester.pumpAndSettle();
      expect(sent, ['b', 'b']);
      expect(find.byKey(const ValueKey('print-preview')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('players view', () {
    testWidgets('a pending move survives Undo removing its section', (
      tester,
    ) async {
      final c = fixture(format: Format.swiss);
      addTearDown(c.dispose);
      await postRound(tester, c);
      c.change(
        'Add section',
        c.event!.copy(
          sections: [
            ...c.event!.sections,
            Section(id: 'extra', name: 'Extra', players: const []),
          ],
        ),
      );
      await mount(tester, c);
      await tester.tap(box(c.event!.sections.first.players.first));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('move-to-extra')));
      await tester.pumpAndSettle();
      expect(find.text('Move to Extra?'), findsOneWidget);
      c.undo();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Move to Extra?'), findsNothing);
      expect(find.text('1 player selected'), findsOneWidget);
    });

    testWidgets('changing the ticks resets a pending swap', (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      final [q1, q2] = c.event!.sections;
      await mount(tester, c);
      await tester.tap(box(q1.players.first));
      await tester.tap(box(q2.players.first));
      await tester.pump();
      await tester.tap(find.text('Swap sections'));
      await tester.pump();
      expect(find.textContaining('Confirm swap'), findsOneWidget);
      await tester.tap(box(q2.players.first));
      await tester.tap(box(q2.players.last));
      await tester.pump();
      expect(find.textContaining('Confirm swap'), findsNothing);
      expect(find.text('Swap sections'), findsOneWidget);
    });

    testWidgets('clicking the open player again shows the card over History', (
      tester,
    ) async {
      final c = fixture();
      addTearDown(c.dispose);
      await mount(tester, c);
      await tester.tap(find.text('Player 00'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPanel), findsOneWidget);
      await tester.tap(find.byTooltip('History (Ctrl+H)'));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryPanel), findsOneWidget);
      expect(find.byType(PlayerPanel), findsNothing);
      await tester.tap(find.text('Player 00').first);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPanel), findsOneWidget);
      expect(find.byType(HistoryPanel), findsNothing);
    });

    testWidgets('New section behind History is shown, not closed', (
      tester,
    ) async {
      final c = fixture();
      addTearDown(c.dispose);
      await mount(tester, c);
      await tester.tap(find.byKey(const ValueKey('new-section')));
      await tester.pumpAndSettle();
      expect(find.byType(NewSectionPanel), findsOneWidget);
      await tester.tap(find.byTooltip('History (Ctrl+H)'));
      await tester.pumpAndSettle();
      expect(find.byType(NewSectionPanel), findsNothing);
      await tester.tap(find.byKey(const ValueKey('new-section')));
      await tester.pumpAndSettle();
      expect(find.byType(NewSectionPanel), findsOneWidget);
      // A second click, with it showing, closes it.
      await tester.tap(find.byKey(const ValueKey('new-section')));
      await tester.pumpAndSettle();
      expect(find.byType(NewSectionPanel), findsNothing);
    });

    testWidgets('the list position is saved when scrolling settles', (
      tester,
    ) async {
      final c = fixture(count: 40);
      addTearDown(c.dispose);
      await mount(tester, c);
      var writes = 0;
      void counted() => writes++;
      c.workspaceState.addListener(counted);
      addTearDown(() => c.workspaceState.removeListener(counted));
      await tester.timedDrag(
        find.text('Player 05'),
        const Offset(0, -400),
        const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(writes, 0);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      expect(writes, 1);
      final saved = c.workspaceState.readMap('players-view-all')['scroll'];
      expect(saved, greaterThan(0));
      // Leaving the page and coming back restores the position.
      await tester.tap(find.text('Pairings').first);
      await tester.pumpAndSettle();
      expect(c.workspaceState.readMap('players-view-all')['scroll'], saved);
      await tester.tap(find.text('Players').first);
      await tester.pumpAndSettle();
      expect(find.text('Player 00'), findsNothing);
    });
  });

  testWidgets('the rating field is locked once pairings are posted', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    await postRound(tester, c);
    await mount(tester, c);
    final player = c.event!.player(c.event!.sections.first.players.first);
    await tester.tap(find.text(player.name).first);
    await tester.pumpAndSettle();
    final rating = find.byKey(const ValueKey('panel-rating'));
    expect(tester.widget<TextField>(rating).enabled, false);
    expect(
      find.text('Pairings are posted; the pairing rating stays.'),
      findsWidgets,
    );
    await tester.enterText(find.byKey(const ValueKey('panel-name')), 'Renamed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.event!.player(player.id).name, 'Renamed');
    expect(c.event!.player(player.id).rating, player.rating);
  });

  testWidgets('the event time control is checked like a section\'s', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventPanel(controller: c, onClose: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('event-time')),
      'sixty minutes',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      find.textContaining('is not in a form US Chess reports use'),
      findsOne,
    );
    expect(c.event!.timeControl, isNot('sixty minutes'));
    await tester.enterText(
      find.byKey(const ValueKey('event-time')),
      'G/60 d/5',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(c.event!.timeControl, 'G/60 d/5');
  });

  testWidgets('a section removed while pairing gives the plain reason', (
    tester,
  ) async {
    final c = fixture(format: Format.swiss);
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    // The round robin cannot be paired, so it comes back as a note.
    c.change(
      'Make a round robin',
      c.event!.copy(
        sections: [
          for (final s in c.event!.sections)
            s.id == q2.id ? s.copy(format: Format.roundRobin) : s,
        ],
      ),
    );
    c.avoidPair(q2.players[0], q2.players[1], true);
    await mount(tester, c);
    await tester.tap(find.text('Pairings').first);
    await tester.pumpAndSettle();
    final before = c.event!.revision;
    await tester.tap(find.byKey(const ValueKey('pair-next-round')));
    // While pairing runs, the round robin is removed.
    c.change(
      'Remove section',
      c.event!.copy(
        sections: [
          for (final s in c.event!.sections)
            if (s.id != q2.id) s,
        ],
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.textContaining('The event changed while pairing'), findsOne);
    expect(c.event!.revision, before + 1);
    expect(c.event!.sections.single.id, q1.id);
  });

  testWidgets('a file without crash protection says to keep backups on', (
    tester,
  ) async {
    final c = TournamentController(_Unprotected())..create('Club night');
    addTearDown(c.dispose);
    await mount(tester, c);
    expect(find.byKey(const ValueKey('crash-unprotected')), findsOneWidget);
    expect(find.textContaining('Keep backups on'), findsOneWidget);
    await tester.tap(find.text('Backups…'));
    await tester.pumpAndSettle();
    expect(find.text('Back up now'), findsNothing);
    expect(find.text('None chosen.'), findsOneWidget);
  });

  testWidgets('a protected file shows no such warning', (tester) async {
    final c = fixture();
    addTearDown(c.dispose);
    await mount(tester, c);
    expect(find.byKey(const ValueKey('crash-unprotected')), findsNothing);
  });

  testWidgets('renaming a section to a taken name says so in the panel', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    final [q1, q2] = c.event!.sections;
    await mount(tester, c);
    await sectionMenu(tester, q1.id, 'Rename / section settings…');
    await tester.enterText(find.byKey(const ValueKey('field-name')), q2.name);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('There is already a section called'), findsOne);
    expect(c.event!.sections.first.name, q1.name);
    expect(find.byKey(const ValueKey('field-name')), findsOneWidget);
  });
}
