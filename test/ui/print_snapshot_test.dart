import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
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
        await tester.tap(find.text('Use older revision ${snapshot.revision}'));
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
          expect(
            find.text('Use older revision ${snapshot.revision}'),
            findsOneWidget,
          );
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
}
