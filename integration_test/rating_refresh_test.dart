import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/infrastructure/ratings_api.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';
import '../test/support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('inline rating review keeps the player editor available', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final c = fixture(count: 4);
    c.savePlayer(c.event!.player('p0').copy(name: 'Maya Patel', rating: 1800));
    c.savePlayer(c.event!.player('p1').copy(name: 'Leo Chen', rating: 1500));
    c.savePlayer(c.event!.player('p2').copy(name: 'Sofia Rivera', rating: 0));
    c.savePlayer(
      c.event!.player('p3').copy(name: 'Alex Kim', memberId: '', rating: 0),
    );
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
            home: Workspace(
              controller: c,
              path: 'Rating review.meow',
              onClose: () {},
              onTheme: () {},
              ratingLookup: (_, id) async => MemberObservation(
                id: id,
                name: {
                  '12000000': 'Maya Patel',
                  '12000001': 'Leo Chen',
                  '12000002': 'Sofia Rivera',
                }[id]!,
                retrievedAt: '2026-10-03',
                supplementDate: '2026-10-01',
                ratings: {
                  'R': {'12000000': 1300, '12000002': 2100}[id],
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('player-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('refresh-uscf')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }
    await tester.pumpAndSettle();
    expect(
      find.text('Found ratings for 2 players. 2 missing — see player rows.'),
      findsOneWidget,
    );
    final playerName = find.text('Maya Patel').first;
    final position = tester.getCenter(playerName);
    await tester.tapAt(position, kind: ui.PointerDeviceKind.mouse);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await tester.tapAt(position, kind: ui.PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panel-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('rating-review')), findsOneWidget);
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

    await capture('rating-review-light');
    dark.value = true;
    await tester.pumpAndSettle();
    await capture('rating-review-dark');
    await tester.binding.setSurfaceSize(const Size(960, 600));
    await tester.pumpAndSettle();
    await capture('rating-review-small');
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep current ratings'));
    await tester.pumpAndSettle();
    expect(c.event!.player('p0').rating, 1800);
    expect(find.byKey(const ValueKey('rating-review')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    c.dispose();
    dark.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}
