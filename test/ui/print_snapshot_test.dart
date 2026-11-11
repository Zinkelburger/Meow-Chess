import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/remembered_printing.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:meow_chess/ui/panels.dart';

import '../support.dart';

class _Printer extends PrintingPlatform {
  final jobs = <({Uint8List bytes, String name})>[];
  @override
  Future<PrintingInfo> info() async => const PrintingInfo(canPrint: true);

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) async {
    jobs.add((bytes: await onLayout(format), name: name));
    return true;
  }

  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Printer printer;
  setUp(() {
    final previous = PrintingPlatform.instance;
    printer = _Printer();
    PrintingPlatform.instance = printer;
    addTearDown(() => PrintingPlatform.instance = previous);
  });

  testWidgets(
    'refresh cancels pending old bytes and prints fresh bytes with their own name',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final old = Completer<Uint8List>(), fresh = Completer<Uint8List>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrintPanel(
              event: c.event!,
              controller: c,
              kind: ReportKind.packet,
              onClose: () {},
              generate: (_) => calls++ == 0 ? old.future : fresh.future,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('print-preview')));
      await tester.pump();
      c.change('Rename event', c.event!.copy(name: 'New revision name'));
      await tester.pump();
      await tester.tap(find.text('Refresh preview'));
      await tester.pump();
      expect(find.byKey(const ValueKey('print-stale')), findsNothing);
      old.complete(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();
      expect(printer.jobs, isEmpty);
      await tester.tap(find.byKey(const ValueKey('print-preview')));
      fresh.complete(Uint8List.fromList([4, 5, 6]));
      await tester.pumpAndSettle();
      expect(printer.jobs, hasLength(1));
      expect(printer.jobs.single.bytes, [4, 5, 6]);
      expect(printer.jobs.single.name, 'New revision name');
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final changeAgain in [false, true]) {
    testWidgets(
      'old report approval applies only to the reviewed revision; changeAgain=$changeAgain',
      (tester) async {
        final c = fixture(count: 4);
        addTearDown(c.dispose);
        final snapshot = c.event!;
        final pending = Completer<Uint8List>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PrintPanel(
                event: snapshot,
                controller: c,
                kind: ReportKind.packet,
                onClose: () {},
                generate: (_) => pending.future,
              ),
            ),
          ),
        );
        c.change('Rename event', c.event!.copy(name: 'New name'));
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('print-preview')))
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Print older version'));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('print-preview')));
        await tester.pump();
        if (changeAgain) {
          c.change('Another edit', c.event!.copy(name: 'Another name'));
          await tester.pump();
        }
        pending.complete(Uint8List.fromList([1, 2, 3]));
        await tester.pumpAndSettle();
        if (changeAgain) {
          expect(printer.jobs, isEmpty);
          expect(find.text('Print older version'), findsOneWidget);
        } else {
          expect(printer.jobs, hasLength(1));
          expect(printer.jobs.single.bytes, [1, 2, 3]);
          expect(printer.jobs.single.name, snapshot.name);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'an event edit during PDF generation prevents unapproved printing',
    (tester) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      final pending = Completer<Uint8List>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrintPanel(
              event: c.event!,
              controller: c,
              kind: ReportKind.packet,
              onClose: () {},
              generate: (_) => pending.future,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('print-preview')));
      await tester.pump();
      c.change('Rename event', c.event!.copy(name: 'New name'));
      pending.complete(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();
      expect(printer.jobs, isEmpty);
      expect(find.byKey(const ValueKey('print-stale')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('standings preview offers the crosstable and file copies', (
    tester,
  ) async {
    final c = fixture(count: 4);
    addTearDown(c.dispose);
    final pending = Completer<Uint8List>();
    Widget panel(ReportKind kind) => MaterialApp(
      home: Scaffold(
        body: PrintPanel(
          event: c.event!,
          controller: c,
          kind: kind,
          onClose: () {},
          generate: (_) => pending.future,
        ),
      ),
    );
    await tester.pumpWidget(panel(ReportKind.standings));
    expect(find.byKey(const ValueKey('print-ranking-kind')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-standings-csv')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-crosstable-text')), findsOneWidget);
    await tester.pumpWidget(panel(ReportKind.packet));
    expect(find.byKey(const ValueKey('print-ranking-kind')), findsNothing);
    expect(find.byKey(const ValueKey('save-standings-csv')), findsNothing);
  });

  group('print panel options', () {
    late Directory dir;
    late List<(String?, PdfPageFormat)> sent;
    late RememberedPrinting service;
    // The paper the plugin reports for the job; the request's when null.
    PdfPageFormat? tray;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('meow-print-panel-');
      addTearDown(() {
        // A save started under the test's fake clock may still hold a file
        // open, which Windows will not delete around.
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Left for the system's temporary-file cleanup.
        }
      });
      sent = [];
      tray = null;
      service = RememberedPrinting(
        preference: PrinterPreference(directory: dir),
        info: () async => const PrintingInfo(
          canPrint: true,
          directPrint: true,
          canListPrinters: true,
        ),
        printers: () async => const [Printer(url: 'club', name: 'Club')],
        send: (printer, layout, _, format) async {
          await layout(tray ?? format);
          sent.add((printer?.url, format));
          return true;
        },
      );
    });

    Widget panel(
      TournamentController c, {
      Future<Uint8List> Function(Event)? generate,
    }) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 900,
          child: PrintPanel(
            event: c.event!,
            controller: c,
            kind: ReportKind.packet,
            onClose: () {},
            printing: service,
            generate: generate ?? (_) async => Uint8List(3),
          ),
        ),
      ),
    );

    testWidgets('Copies and options opens the system window, no printer', (
      tester,
    ) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1200, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(panel(c));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('print-system-dialog')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(sent, [(null, PdfPageFormat.letter)]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('choosing A4 regenerates the preview and is remembered', (
      tester,
    ) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1200, 1400);
      addTearDown(tester.view.reset);
      var generated = 0;
      await tester.pumpWidget(
        panel(
          c,
          generate: (_) async {
            generated++;
            return Uint8List(3);
          },
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(generated, 1);
      await chooseOption(
        tester,
        find.byKey(const ValueKey('print-paper')),
        'A4',
      );
      expect(generated, 2);
      expect(service.pageFormat, PdfPageFormat.a4);
      // The write is real file I/O started inside the test's fake clock.
      var remembered = false;
      for (var i = 0; i < 100 && !remembered; i++) {
        await tester.pump();
        remembered =
            await tester.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 5));
              return service.preference.readA4();
            }) ??
            false;
      }
      expect(remembered, true);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a saved A4 preference is applied when the panel opens', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await service.preference.writeA4(true);
        await service.loadPaper();
      });
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1200, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(panel(c));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('print-preview')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      // First print asks for a printer here, in the panel.
      await tester.tap(find.byKey(const ValueKey('print-to-printer')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(sent, [('club', PdfPageFormat.a4)]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Save PDF waits for approval of an out-of-date preview', (
      tester,
    ) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1200, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(panel(c));
      await tester.pump();
      TextButton save() =>
          tester.widget<TextButton>(find.byKey(const ValueKey('save-pdf')));
      expect(save().onPressed, isNotNull);
      c.change('Rename event', c.event!.copy(name: 'New name'));
      await tester.pump();
      expect(save().onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a print on other paper than the preview says so', (
      tester,
    ) async {
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(1200, 1400);
      addTearDown(tester.view.reset);
      tray = PdfPageFormat.a4;
      await tester.pumpWidget(panel(c));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.byKey(const ValueKey('print-paper-note')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('print-system-dialog')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Printed on A4 to match the printer.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
