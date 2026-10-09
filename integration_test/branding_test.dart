import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/main.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/ui/brand.dart';
import 'package:meow_chess/ui/desktop_window.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('bundled branding loads with native window decorations', (
    tester,
  ) async {
    await initializeDesktopWindow();
    final directory = Directory.systemTemp.createTempSync('meow-branding-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final screenshotKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: MeowApp(dataDirectory: directory),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> screenshot(String name) async {
      final boundary =
          screenshotKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('artifacts').createSync();
      await File(
        'artifacts/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(manifest.listAssets(), contains('assets/icon/meow_chess.png'));
    final logo = await rootBundle.load('assets/icon/meow_chess.png');
    final codec = await ui.instantiateImageCodec(logo.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    expect(frame.image.width, greaterThan(0));
    frame.image.dispose();
    codec.dispose();
    expect(find.byType(WorkspaceToolbar), findsNothing);
    expect(find.byType(MeowLogo), findsOneWidget);
    await screenshot('branding-welcome');
    expect(find.text('Try a practice event'), findsNothing);
    final eventPath = '${directory.path}/club.meow';
    final event = TournamentController(SqliteEventRepository(eventPath));
    event.create('Saturday at the club');
    event.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: MeowApp(dataDirectory: directory, initialPath: eventPath),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceToolbar), findsOneWidget);
    expect(find.byType(MeowLogo), findsNothing);
    expect(find.text('Saturday at the club'), findsWidgets);
    await screenshot('branding-workspace');
    await tester.tap(find.byTooltip('Dark mode'));
    await tester.pumpAndSettle();
    await screenshot('branding-workspace-dark');
    await tester.tap(find.byTooltip('Close event'));
    await tester.pumpAndSettle();
    expect(find.text('Recent events'), findsOneWidget);
    expect(find.byType(MeowLogo), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
