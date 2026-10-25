import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/main.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/domain/swiss.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'generate synthetic Swiss, inspect replay and reopen saved evidence',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('meow simulation ');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        folder.deleteSync(recursive: true);
      });
      await tester.pumpWidget(MeowApp(dataDirectory: folder));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate a practice tournament'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('field-players')), '8');
      await tester.enterText(find.byKey(const ValueKey('field-rounds')), '3');
      await tester.enterText(find.byKey(const ValueKey('field-seed')), '123');
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();
      expect(find.text('Practice copy'), findsOneWidget);
      await tester.tap(find.text('Reports').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('pairing-checklist')),
      );
      await tester.tap(find.byKey(const ValueKey('pairing-checklist')));
      await tester.pumpAndSettle();
      for (
        var n = 0;
        n < 50 && find.byType(SelectableText).evaluate().isEmpty;
        n++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.textContaining('Replay: matches saved proposal.'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .join('\n'),
      );
      expect(find.textContaining('not US Chess certification'), findsOneWidget);
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close event'));
      await tester.pumpAndSettle();
      final recent =
          jsonDecode(File('${folder.path}/library.json').readAsStringSync())
              as List;
      final saved = SqliteEventRepository(recent.single as String);
      final event = saved.load()!;
      expect(event.practice, true);
      expect(event.players, hasLength(8));
      expect(event.sections.single.rounds, hasLength(3));
      for (final r in event.sections.single.rounds) {
        expect(recheckPairing(r), isEmpty);
      }
      saved.close();
      expect(tester.takeException(), isNull);
    },
  );
}
