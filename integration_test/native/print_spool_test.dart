// The real printing plugin, sending real jobs to the operating system's
// spooler, through the same service the print panel uses. The stand-in queue
// comes from scripts/check_native_print.py, which then reads what arrived.
// It lives apart from the integration_test/*_test.dart that CI runs in a loop,
// and it refuses to run without a queue named for testing, so it can never send
// a page to a real printer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/remembered_printing.dart';
import 'package:meow_chess/infrastructure/reports.dart';
import 'package:path/path.dart' as path;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../test/pdf_geometry.dart';
import '../../test/print_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final queue = env['MEOW_PRINT_QUEUE'];
  final out = env['MEOW_PRINT_OUT'];
  // Windows' print-to-file port has one output file; each job is moved aside.
  final portFile = env['MEOW_PRINT_PORT_FILE'];

  testWidgets(
    'jobs reach the system spooler whole, on the saved printer',
    (tester) async {
      expect(queue, startsWith('meow-virtual'), reason: 'test queues only');
      await tester.runAsync(() async {
        final font = pw.Font.ttf(
          await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
        );
        final bold = pw.Font.ttf(
          await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'),
        );
        final settings = Directory.systemTemp.createTempSync('meow-spool-');
        addTearDown(() => settings.deleteSync(recursive: true));
        final service = RememberedPrinting(
          preference: PrinterPreference(directory: settings),
        );

        expect([
          for (final p in await service.available()) p.name,
        ], contains(queue));

        final jobs = <(String, Event, ReportKind, int?, bool, List<String>)>[
          (
            'quad',
            printQuad(),
            ReportKind.pairings,
            null,
            false,
            ['Alexandra', 'Round-robin'],
          ),
          (
            'round-robin',
            printRoundRobin(),
            ReportKind.pairings,
            null,
            false,
            ['Montgomery', 'Board'],
          ),
          (
            'swiss-wall-chart',
            printSwiss(),
            ReportKind.wallChart,
            null,
            false,
            ['Wall', 'Montgomery'],
          ),
          (
            'swiss-round',
            printSwiss(),
            ReportKind.pairings,
            3,
            false,
            ['Board', 'White'],
          ),
          // Windows prints on the driver's own paper, whatever the PDF says,
          // so A4 has nothing to show on a Letter default; see docs/TESTING.md.
          if (!Platform.isWindows)
            (
              'quad-a4',
              printQuad(),
              ReportKind.pairings,
              null,
              true,
              ['Alexandra'],
            ),
        ];

        var picks = 0;
        final expected = <Map<String, Object>>[];
        for (final (i, job) in jobs.indexed) {
          final (name, event, kind, round, a4, words) = job;
          final bytes = await reportPdf(
            event,
            kind,
            roundNumber: round,
            a4: a4,
            font: font,
            bold: bold,
          );
          final pages = pdfPages(bytes);
          service.a4 = a4;
          final sent = await service.print(
            bytes,
            'meow-$name',
            choose: (found) async {
              picks++;
              return found.firstWhere((p) => p.name == queue);
            },
          );
          expect(sent, isTrue, reason: name);
          if (portFile != null) {
            await _collect(File(portFile), path.join(out!, 'job-$i.pdf'));
          }
          expected.add({
            'name': name,
            'pages': pages.length,
            'width': pages.first.width,
            'height': pages.first.height,
            'words': words,
          });
        }
        expect(picks, 1, reason: 'later jobs use the saved printer');
        expect((await service.preference.read())?.name, queue);

        // A printer that has gone away is an error the TD can read, never a
        // silent "sent" or a hang. The plugin also raises its error before
        // anything awaits it, so this zone takes that stray copy.
        final gone = Completer<Object?>();
        runZonedGuarded(() async {
          try {
            await service.send(
              const Printer(
                url: 'meow-virtual-gone',
                name: 'meow-virtual-gone',
              ),
              await reportPdf(printQuad(), ReportKind.pairings),
              'meow-gone',
              PdfPageFormat.letter,
            );
            gone.complete(null);
          } catch (error) {
            gone.complete(error);
          }
        }, (_, _) {});
        expect(
          await gone.future.timeout(const Duration(seconds: 60)),
          isA<TournamentException>(),
        );

        File(
          path.join(out!, 'expected.json'),
        ).writeAsStringSync(jsonEncode(expected));
      });
    },
    skip: queue == null || out == null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// Waits for the port file to appear and stop growing, then moves it.
Future<void> _collect(File port, String destination) async {
  var last = -1;
  for (var tries = 0; tries < 120; tries++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!port.existsSync()) continue;
    final size = port.lengthSync();
    if (size > 0 && size == last) {
      try {
        port.renameSync(destination);
        return;
      } on FileSystemException {
        // The spooler still has it open.
      }
    }
    last = size;
  }
  throw StateError('No job reached ${port.path}');
}
