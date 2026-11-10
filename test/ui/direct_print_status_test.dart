import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/infrastructure/remembered_printing.dart';
import 'package:meow_chess/ui/panels.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';

import '../support.dart';
import 'workspace_host.dart';

class _MemoryPreference extends PrinterPreference {
  _MemoryPreference(this.saved);
  Printer? saved;
  @override
  Future<Printer?> read() async => saved;
  @override
  Future<void> write(Printer printer) async => saved = printer;
}

/// Stands in for the plugin where the print panel draws its preview.
class _Platform extends PrintingPlatform {
  @override
  Future<PrintingInfo> info() async => const PrintingInfo(canPrint: true);

  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const club = Printer(url: 'club', name: 'Club printer');

void main() {
  final status = find.byKey(const ValueKey('status-print'));

  /// Lets the sheet be built (fonts, PDF) and the print service answer.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), true);
  }

  testWidgets('a direct print says where it is going and when it has gone', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    final sent = <String?>[];
    final job = Completer<bool>();
    final printing = RememberedPrinting(
      preference: _MemoryPreference(club),
      info: () async => const PrintingInfo(
        canPrint: true,
        directPrint: true,
        canListPrinters: true,
      ),
      printers: () async => const [club],
      // A slow printer: the job stays in flight until the test lets it go.
      send: (printer, _, _, _) {
        sent.add(printer?.url);
        return job.future;
      },
    );
    await mountWorkspace(tester, c, printing: printing);
    final tabs = tester.getRect(find.byKey(const ValueKey('section-tabs')));
    final bar = tester.getRect(find.byKey(const ValueKey('status-bar')));
    // A live region, there before there is anything to say.
    expect(tester.widget<Semantics>(status).properties.liveRegion, true);
    expect(find.textContaining('Sending to'), findsNothing);

    await chord(tester, LogicalKeyboardKey.keyP);
    await settle(tester, () => sent.isNotEmpty);
    expect(
      find.descendant(
        of: status,
        matching: find.text('Sending to Club printer…'),
      ),
      findsOneWidget,
    );
    // Nothing on the page moves for it, and no panel opens.
    expect(tester.getRect(find.byKey(const ValueKey('section-tabs'))), tabs);
    expect(tester.getRect(find.byKey(const ValueKey('status-bar'))), bar);
    expect(find.byType(PrintPanel), findsNothing);

    // A second press, by key or from a tab's menu, sends nothing more.
    await chord(tester, LogicalKeyboardKey.keyP);
    await tester.tap(find.byKey(const ValueKey('section-menu-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print wall chart'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(sent, ['club']);
    expect(
      find.descendant(
        of: status,
        matching: find.text('Already printing · Sending to Club printer…'),
      ),
      findsOneWidget,
    );

    job.complete(true);
    await settle(
      tester,
      () => find.text('Sent to Club printer').evaluate().isNotEmpty,
    );
    expect(sent, ['club']);
    expect(find.textContaining('Sending to'), findsNothing);
    expect(tester.getRect(find.byKey(const ValueKey('status-bar'))), bar);

    // The note leaves by itself, and the next print goes out.
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('Sent to Club printer'), findsNothing);
    final again = Completer<void>();
    final second = RememberedPrinting(
      preference: _MemoryPreference(club),
      info: printing.info,
      printers: printing.printers,
      send: (printer, _, _, _) async {
        sent.add(printer?.url);
        again.complete();
        return true;
      },
    );
    await mountWorkspace(tester, c, printing: second);
    await chord(tester, LogicalKeyboardKey.keyP);
    await settle(tester, () => again.isCompleted);
    expect(sent, ['club', 'club']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed print says why and clears the status line', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    var tries = 0;
    final printing = RememberedPrinting(
      preference: _MemoryPreference(club),
      info: () async => const PrintingInfo(
        canPrint: true,
        directPrint: true,
        canListPrinters: true,
      ),
      printers: () async => const [club],
      send: (_, _, _, _) async {
        tries++;
        throw 'Club printer is out of paper.';
      },
    );
    await mountWorkspace(tester, c, printing: printing);
    await chord(tester, LogicalKeyboardKey.keyP);
    await settle(tester, () => tries == 1);
    await tester.pump();
    expect(find.textContaining('out of paper'), findsOneWidget);
    expect(find.textContaining('Sending to'), findsNothing);
    expect(find.textContaining('Sent to'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with no printer remembered the print panel asks for one', (
    tester,
  ) async {
    final previous = PrintingPlatform.instance;
    PrintingPlatform.instance = _Platform();
    addTearDown(() => PrintingPlatform.instance = previous);
    final c = fixture();
    addTearDown(c.dispose);
    final sent = <String?>[];
    final printing = RememberedPrinting(
      preference: _MemoryPreference(null),
      info: () async => const PrintingInfo(
        canPrint: true,
        directPrint: true,
        canListPrinters: true,
      ),
      printers: () async => const [club],
      send: (printer, _, _, _) async {
        sent.add(printer?.url);
        return true;
      },
    );
    await mountWorkspace(tester, c, printing: printing);
    await chord(tester, LogicalKeyboardKey.keyP);
    await settle(tester, () => find.byType(PrintPanel).evaluate().isNotEmpty);
    expect(sent, isEmpty);
    // The panel has taken over from the status line.
    expect(find.textContaining('Sending to'), findsNothing);
    expect(find.textContaining('Sent to'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
