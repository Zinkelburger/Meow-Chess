import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../test/support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('inline feedback survives desktop themes and large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final c = fixture(count: 4);
    c.savePlayer(c.event!.player('p0').copy(name: 'Maya Patel'));
    c.savePlayer(c.event!.player('p1').copy(name: 'Leo Chen'));
    c.savePlayer(c.event!.player('p2').copy(name: 'Sofia Rivera'));
    c.savePlayer(c.event!.player('p3').copy(name: 'Alex Kim'));
    c.post(await c.propose());
    final game = c.event!.games.first;
    final boundaryKey = GlobalKey();
    final dark = ValueNotifier(false);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: ValueListenableBuilder(
          valueListenable: dark,
          builder: (_, isDark, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: meowTheme(isDark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(isDark ? 2 : 1)),
              child: child!,
            ),
            home: Workspace(
              controller: c,
              path: 'Club tournament.meow',
              onClose: () {},
              onTheme: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pairings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('game-${game.id}')));
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
    await tester.pumpAndSettle();
    expect(c.event!.games.first.outcome, Outcome.whiteForfeit);
    expect(find.text('Withdraw from future rounds'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('artifacts').createSync();
      await File(
        'artifacts/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    await capture('inline-forfeit-light');
    dark.value = true;
    await tester.binding.setSurfaceSize(const Size(960, 700));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Withdraw from future rounds'));
    await tester.pumpAndSettle();
    await capture('inline-forfeit-dark-200');
    await tester.tap(find.text('Withdraw from future rounds'));
    await tester.pumpAndSettle();
    expect(c.event!.player(game.black).withdrawn, true);
    expect(find.text('Withdrawn'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('undo')));
    await tester.pumpAndSettle();
    expect(c.event!.player(game.black).withdrawn, false);
    dark.value = false;
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.tap(find.text('Players'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('player-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('paste-roster')),
      'Name,Rating\nMorgan Lee,1500\nRobin Brooks,1600',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review import'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-roster-import')));
    await tester.pumpAndSettle();
    expect(find.text('Imported 2 players'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await capture('inline-import-light');
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(c.event!.players, hasLength(4));
    expect(find.text('Imported 2 players'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    c.dispose();
    dark.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
