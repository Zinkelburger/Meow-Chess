import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';

import '../test/support.dart';

/// Section settings → Pairing rules for an ordinary US Chess Swiss, and the
/// trip to the event's tie-breaks and back. Screenshots go to
/// artifacts/pairing-rules/.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Pairing rules and the tie-break detour', (tester) async {
    final c = fixture(count: 9, format: Format.swiss);
    final boundaryKey = GlobalKey();
    final dark = ValueNotifier(false);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
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
              path: 'Tuesday Swiss.meow',
              onClose: () {},
              onTheme: () => dark.value = !dark.value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'artifacts/pairing-rules/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    }

    final section = c.event!.sections.firstWhere(
      (s) => s.format == Format.swiss,
    );
    final chip = find.byKey(ValueKey('section-chip-${section.id}'));
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename / section settings…'));
    await tester.pumpAndSettle();
    final header = find.byKey(const ValueKey('section-group-pairing'));
    await tester.ensureVisible(header);
    await capture('1-closed');
    await tester.tap(header);
    await tester.pumpAndSettle();
    await tester.ensureVisible(header);
    await capture('2-open');
    final link = find.byKey(const ValueKey('field-event-tiebreaks'));
    await tester.ensureVisible(link);
    await capture('3-open-bottom');
    await tester.tap(link);
    await capture('4-event');
    // Event details opened from the section's settings names the way back,
    // and its close button returns there rather than to the bare table.
    expect(find.byKey(const ValueKey('panel-back')), findsOneWidget);
    await tester.tap(find.byTooltip(RegExp('^Back to .* settings')));
    await capture('5-after-close');
    expect(find.byKey(const ValueKey('panel-back')), findsNothing);
    expect(find.byKey(const ValueKey('field-event-tiebreaks')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('field-variations-group')));
    await capture('5b-variations-open');
    dark.value = true;
    await capture('6-after-close-dark');
  });
}
