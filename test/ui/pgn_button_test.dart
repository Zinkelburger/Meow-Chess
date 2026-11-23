import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/ui/panels.dart';

import '../support.dart';

void main() {
  final saved = <(String, String)>[];
  Widget panel(TournamentController c, ReportKind kind, {int? round}) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 900,
            child: PrintPanel(
              event: c.event!,
              controller: c,
              kind: kind,
              roundNumber: round,
              onClose: () {},
              generate: (_) async => Uint8List(3),
              saveFile: (name, bytes) async {
                saved.add((name, utf8.decode(bytes)));
                return '/tmp/$name';
              },
            ),
          ),
        ),
      );

  testWidgets('pairing sheets save their rounds as PGN headers', (
    tester,
  ) async {
    saved.clear();
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1200, 1400);
    addTearDown(tester.view.reset);

    // Nothing is paired yet: there is nothing to save.
    await tester.pumpWidget(panel(c, ReportKind.packet));
    await tester.pump();
    expect(find.byKey(const ValueKey('save-pgn')), findsNothing);
    await tester.pumpWidget(const SizedBox());

    final batch = await tester.runAsync(c.propose);
    c.post(batch!);
    await tester.pumpWidget(panel(c, ReportKind.packet));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('save-pgn')));
    await tester.tap(find.byKey(const ValueKey('save-pgn')));
    // The preview keeps animating, so settle by hand.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final (name, pgn) = saved.single;
    expect(name, 'games-r${c.event!.revision}.pgn');
    expect('[Round "1"]'.allMatches(pgn), hasLength(2));
    expect(pgn, contains('[Result "*"]'));
    expect(find.text('Saved to /tmp/$name'), findsOne);
    await tester.pumpWidget(const SizedBox());

    // A player list has no games to save.
    await tester.pumpWidget(panel(c, ReportKind.sections));
    await tester.pump();
    expect(find.byKey(const ValueKey('save-pgn')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
