import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/ui/theme.dart';
import 'package:meow_chess/ui/workspace.dart';

import '../test/support.dart';

/// FIDE support in the real desktop renderer: a dual-rated Swiss paired by
/// the FIDE Dutch engine, the section, player and event panels, and the
/// FIDE report beside the US Chess one. Screenshots go to artifacts/.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('FIDE-rated section from settings to report', (tester) async {
    final c = fixture(count: 9, format: Format.swiss);
    final boundaryKey = GlobalKey();
    final scale = ValueNotifier(1.0);
    final dark = ValueNotifier(false);
    // One Swiss of nine, dual rated, with FIDE identities for most.
    final e = c.event!;
    final everyone = [for (final s in e.sections) ...s.players];
    c.change(
      'Set up FIDE open',
      e.copy(
        city: 'Boston',
        fide: const FideRegistration(
          chiefArbiter: FideOfficial(name: 'Ada Arbiter'),
        ),
        players: [
          for (final (i, p) in e.players.indexed)
            i == 8
                ? p
                : p.copy(
                    fideId: '${2000100 + i}',
                    fideStandard: 1950 - i * 45,
                    federation: 'USA',
                    title: i == 0 ? 'FM' : '',
                  ),
        ],
        sections: [
          e.sections.first.copy(
            name: 'Open',
            players: everyone,
            plannedRounds: 4,
            fideRated: true,
          ),
        ],
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: ValueListenableBuilder(
          valueListenable: dark,
          builder: (_, isDark, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: meowTheme(isDark ? Brightness.dark : Brightness.light),
            builder: (context, child) => ValueListenableBuilder(
              valueListenable: scale,
              builder: (_, value, _) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(value)),
                child: child!,
              ),
            ),
            home: Workspace(
              controller: c,
              path: 'Fall FIDE Open.meow',
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
        'artifacts/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    }

    final section = c.event!.sections.single;
    // Round 1 by the FIDE Dutch engine, through the app's own command.
    final batch = await c.propose(sectionId: section.id);
    expect(batch.issues, isEmpty);
    expect(batch.rounds[section.id]!.policy, 'fide-dutch-2026-bbp-6');
    c.post(batch);
    await tester.pumpAndSettle();

    // Section settings.
    final chip = find.byKey(ValueKey('section-chip-${section.id}'));
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename / section settings…'));
    await tester.pumpAndSettle();
    await capture('fide-section-settings');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Player panel for the player without a FIDE ID.
    await tester.tap(find.text('Player 08').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('panel-sex')));
    await capture('fide-player-panel');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Player tools → FIDE ratings (no list installed on a test machine).
    await tester.tap(find.byKey(const ValueKey('player-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fide-ratings')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 1)));
    await capture('fide-ratings-panel');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Export: the FIDE region and its checks.
    await tester.tap(find.text('Export').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('fide-report')));
    await capture('fide-report-light');
    await tester.tap(find.text('Edit FIDE details').first);
    await tester.pumpAndSettle();
    await capture('fide-event-panel');
    await tester.ensureVisible(
      find.byKey(const ValueKey('event-group-tiebreaks')),
    );
    await capture('fide-event-tiebreaks-closed');
    await tester.tap(find.byKey(const ValueKey('event-group-tiebreaks')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('event-fide-tiebreaks')),
    );
    await capture('fide-event-tiebreaks');
    dark.value = true;
    await capture('fide-report-dark');
    dark.value = false;
    scale.value = 2.0;
    await capture('fide-report-200');
  });
}
