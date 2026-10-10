import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/fide_rating_list.dart';
import 'package:meow_chess/ui/fide_list_panel.dart';
import 'package:meow_chess/ui/theme.dart';

import '../support.dart';

void main() {
  testWidgets('checks the event against the FIDE list and applies', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('fide-panel-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final list = FideRatingList(Directory('${dir.path}/fide'));
    await tester.runAsync(() async {
      final txt = File('test/fixtures/fide/players_list_foa.txt');
      final zip = File('${dir.path}/players_list.zip')
        ..writeAsBytesSync(
          ZipEncoder().encodeBytes(
            Archive()..addFile(
              ArchiveFile.bytes('players_list_foa.txt', txt.readAsBytesSync()),
            ),
          ),
        );
      await list.importZip(zip.path, published: DateTime.utc(2026, 10, 1));
    });
    final c = fixture(count: 4, format: Format.swiss);
    addTearDown(c.dispose);
    final e = c.event!;
    c.change(
      'FIDE',
      e.copy(
        sections: [e.sections.single.copy(fideRated: true)],
        players: [
          for (final p in e.players)
            p.id == 'p0'
                ? p.copy(fideId: '2016192', fideStandard: 2700)
                : p.id == 'p1'
                ? p.copy(fideId: '9999999')
                : p,
        ],
      ),
    );
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    // The panel reads the list with real file I/O and isolates, so it runs
    // outside the fake clock.
    Future<void> settle() => tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          theme: meowTheme(Brightness.light),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) =>
                  FideListPanel(controller: c, onClose: () {}, list: list),
            ),
          ),
        ),
      ),
    );
    await settle();
    expect(find.text('October 2026 list'), findsOneWidget);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('fide-list-check'))),
    );
    await settle();
    expect(find.byKey(const ValueKey('fide-change-p0')), findsOneWidget);
    expect(find.textContaining('Standard 2700 → 2792'), findsOneWidget);
    expect(find.textContaining('Not on the list: Player 01'), findsOneWidget);
    expect(find.textContaining('No FIDE ID yet'), findsOneWidget);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('fide-list-apply'))),
    );
    await settle();
    final p0 = c.event!.player('p0');
    expect(p0.fideStandard, 2792);
    expect(p0.title, 'GM');
    expect(p0.fideEvidence['list'], '2026-10');
    expect(find.textContaining('Updated 1 player'), findsOneWidget);
  });
}
