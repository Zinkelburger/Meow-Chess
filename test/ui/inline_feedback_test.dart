import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/event_panel.dart';
import 'package:meow_chess/ui/reports_view.dart';
import 'package:meow_chess/ui/results_view.dart';
import 'package:meow_chess/ui/theme.dart';
import '../support.dart';

void main() {
  testWidgets(
    'forfeit withdrawal stays with the right player and follows undo',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.post((await tester.runAsync(() => c.propose()))!);
      final game = c.event!.games.first;
      await tester.pumpWidget(
        MaterialApp(
          theme: meowTheme(Brightness.light),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => ResultsView(controller: c),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('game-${game.id}')));
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
      await tester.pumpAndSettle();
      expect(c.event!.games.first.outcome, Outcome.whiteForfeit);
      final withdraw = find.byKey(
        ValueKey('withdraw-${game.id}-${game.black}'),
      );
      expect(withdraw, findsOneWidget);
      expect(
        find.byKey(ValueKey('withdraw-${game.id}-${game.white}')),
        findsNothing,
      );
      expect(find.byType(SnackBar), findsNothing);
      await tester.pump(const Duration(minutes: 1));
      expect(withdraw, findsOneWidget);
      await tester.tap(withdraw);
      await tester.pumpAndSettle();
      expect(c.event!.player(game.black).withdrawn, true);
      expect(find.text('Withdrawn'), findsOneWidget);
      expect(withdraw, findsNothing);
      c.undo();
      await tester.pumpAndSettle();
      expect(c.event!.player(game.black).withdrawn, false);
      expect(withdraw, findsOneWidget);
      c.recordResult(game.id, Outcome.doubleForfeit);
      await tester.pumpAndSettle();
      expect(find.text('Withdraw from future rounds'), findsNWidgets(2));
      c.recordResult(game.id, Outcome.draw);
      await tester.pumpAndSettle();
      expect(find.text('Withdraw from future rounds'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved report path stays inline and identifies newer changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    c.repository.writePreference(
      'lastExport',
      '/tmp/Club reports/october|${c.event!.revision}',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => ReportsView(controller: c),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Includes the current event revision.'),
      findsOneWidget,
    );
    expect(find.textContaining('/tmp/Club reports/october'), findsOneWidget);
    c.savePlayer(c.event!.players.first.copy(name: 'Corrected name'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Newer changes are not included.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Includes the current event revision.'),
      findsNothing,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save copy keeps a selectable receipt beside the control', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('meow-inline-copy-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    const channel = MethodChannel('meow_chess/file_save');
    var cancel = false;
    final path = '${dir.path}/Tournament copy.meow';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => cancel ? null : path,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackupsPanel(controller: c, onClose: () {}),
        ),
      ),
    );
    await tester.tap(find.text('Save copy…'));
    await tester.pumpAndSettle();
    expect(File(path).existsSync(), true);
    expect(find.text('Copy saved to $path'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(minutes: 1));
    cancel = true;
    await tester.tap(find.text('Save copy…'));
    await tester.pumpAndSettle();
    expect(find.text('Copy saved to $path'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
