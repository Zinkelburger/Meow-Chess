import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/remembered_printing.dart';

void main() {
  const a = Printer(url: 'printer-a', name: 'Club printer');
  const b = Printer(url: 'printer-b', name: 'Office printer');
  const direct = PrintingInfo(
    canPrint: true,
    directPrint: true,
    canListPrinters: true,
  );
  final bytes = Uint8List.fromList([1, 2, 3]);
  late Directory dir;
  late PrinterPreference preference;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('meow-printer-test-');
    preference = PrinterPreference(directory: dir);
  });
  tearDown(() async => dir.delete(recursive: true));

  test('first print remembers the device across service instances', () async {
    final sent = <String?>[];
    var picks = 0;
    RememberedPrinting service() => RememberedPrinting(
      preference: preference,
      info: () async => direct,
      printers: () async => [a, b],
      send: (p, data, name, _) async {
        expect(data, bytes);
        sent.add(p?.url);
        return true;
      },
    );
    Future<Printer?> choose(List<Printer> _) async {
      picks++;
      return b;
    }

    expect(await service().print(bytes, 'Event A', choose: choose), true);
    expect(await service().print(bytes, 'Event B', choose: choose), true);
    expect(picks, 1);
    expect(sent, [b.url, b.url]);
    expect((await preference.read())?.name, b.name);
  });

  test(
    'missing saved printer prompts for a replacement; change printer overrides it',
    () async {
      await preference.write(a);
      final sent = <String?>[];
      final service = RememberedPrinting(
        preference: preference,
        info: () async => direct,
        printers: () async => [b],
        send: (p, _, _, _) async {
          sent.add(p?.url);
          return true;
        },
      );
      var picks = 0;
      Future<Printer?> choose(List<Printer> ps) async {
        picks++;
        return ps.single;
      }

      await service.print(bytes, 'Sheets', choose: choose);
      await service.print(bytes, 'Sheets', choose: choose, changePrinter: true);
      expect(picks, 2);
      expect(sent, [b.url, b.url]);
    },
  );

  test('cancellation never submits or overwrites the saved device', () async {
    await preference.write(a);
    var sends = 0;
    final service = RememberedPrinting(
      preference: preference,
      info: () async => direct,
      printers: () async => [a, b],
      send: (_, _, _, _) async {
        sends++;
        return true;
      },
    );
    expect(
      await service.print(
        bytes,
        'Sheets',
        choose: (_) async => null,
        changePrinter: true,
      ),
      false,
    );
    expect(sends, 0);
    expect((await preference.read())?.url, a.url);
  });

  test(
    'failed job is not retried and does not remember an untested printer',
    () async {
      var sends = 0;
      final service = RememberedPrinting(
        preference: preference,
        info: () async => direct,
        printers: () async => [a],
        send: (_, _, _, _) async {
          sends++;
          throw StateError('offline');
        },
      );
      await expectLater(
        service.print(bytes, 'Sheets', choose: (_) async => a),
        throwsStateError,
      );
      expect(sends, 1);
      expect(service.busy, false);
      expect(await preference.read(), isNull);
    },
  );

  test('unsupported direct printing uses the system dialog', () async {
    final service = RememberedPrinting(
      preference: preference,
      info: () async => const PrintingInfo(canPrint: true),
      printers: () async => throw StateError('should not enumerate'),
      send: (p, _, _, _) async {
        expect(p, isNull);
        return true;
      },
    );
    expect(
      await service.print(
        bytes,
        'Sheets',
        choose: (_) async => throw StateError('should not choose'),
      ),
      true,
    );
  });

  test('no available printers produces a useful error', () async {
    final service = RememberedPrinting(
      preference: preference,
      info: () async => direct,
      printers: () async => [],
      send: (_, _, _, _) async => throw StateError('should not submit'),
    );
    await expectLater(
      service.print(bytes, 'Sheets', choose: (_) async => a),
      throwsA(isA<TournamentException>()),
    );
  });
  for (final directPrint in [false, true]) {
    test(
      'invalidated job is cancelled at the send boundary; direct=$directPrint',
      () async {
        var valid = true;
        var sends = 0;
        final service = RememberedPrinting(
          preference: preference,
          info: () async {
            if (!directPrint) valid = false;
            return directPrint ? direct : const PrintingInfo(canPrint: true);
          },
          printers: () async => [a],
          send: (_, _, _, _) async {
            sends++;
            return true;
          },
        );
        expect(
          await service.print(
            bytes,
            'Sheets',
            canSend: () => valid,
            choose: (_) async {
              valid = false;
              return a;
            },
          ),
          false,
        );
        expect(sends, 0);
        expect(service.busy, false);
        expect(await preference.read(), isNull);
      },
    );
  }

  test('the chosen paper reaches the job and survives a restart', () async {
    expect(await preference.readA4(), false);
    await preference.writeA4(true);
    expect(await PrinterPreference(directory: dir).readA4(), true);
    final formats = <PdfPageFormat>[];
    final service = RememberedPrinting(
      preference: preference,
      info: () async => direct,
      printers: () async => [a],
      send: (_, _, _, format) async {
        formats.add(format);
        return true;
      },
    );
    await service.print(bytes, 'Letter', choose: (_) async => a);
    await service.loadPaper();
    await service.print(bytes, 'Sheets', choose: (_) async => a);
    await service.printWithDialog(bytes, 'Sheets');
    expect(formats, [PdfPageFormat.letter, PdfPageFormat.a4, PdfPageFormat.a4]);
  });

  test('a damaged paper file means Letter, never a failed print', () async {
    await File('${dir.path}/paper.json').writeAsString('{not json');
    expect(await preference.readA4(), false);
  });

  test('the print window offers no printer and keeps the saved one', () async {
    await preference.write(a);
    final sent = <String?>[];
    final service = RememberedPrinting(
      preference: preference,
      info: () async => direct,
      printers: () async => throw StateError('should not enumerate'),
      send: (p, _, _, _) async {
        sent.add(p?.url);
        return true;
      },
    );
    expect(await service.printWithDialog(bytes, 'Sheets'), true);
    expect(sent, [null]);
    expect((await preference.read())?.url, a.url);
  });

  test(
    'a cancelled print window sends nothing further and frees the job',
    () async {
      var sends = 0;
      final service = RememberedPrinting(
        preference: preference,
        info: () async => direct,
        send: (_, _, _, _) async {
          sends++;
          return false;
        },
      );
      expect(await service.printWithDialog(bytes, 'Sheets'), false);
      expect(sends, 1);
      expect(service.busy, false);
    },
  );

  test('an invalidated job never opens the print window', () async {
    var sends = 0;
    final service = RememberedPrinting(
      preference: preference,
      info: () async => direct,
      send: (_, _, _, _) async {
        sends++;
        return true;
      },
    );
    expect(
      await service.printWithDialog(bytes, 'Sheets', canSend: () => false),
      false,
    );
    expect(sends, 0);
  });

  test('offline printers are not offered', () async {
    final service = RememberedPrinting(
      preference: preference,
      printers: () async => const [
        Printer(url: 'on', name: 'On'),
        Printer(url: 'off', name: 'Off', isAvailable: false),
      ],
    );
    expect((await service.available()).map((p) => p.url), ['on']);
  });

  test('GTK file and LPR entries are not printers on Linux', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final service = RememberedPrinting(
      preference: preference,
      info: () async => direct,
      printers: () async => const [
        Printer(url: 'Print to File', name: 'Print to File'),
        Printer(url: 'Print to LPR', name: 'Print to LPR'),
      ],
    );
    // So a Linux computer with no printers gets the useful error.
    await expectLater(
      service.print(bytes, 'Sheets', choose: (_) async => a),
      throwsA(isA<TournamentException>()),
    );
  });

  test(
    'a print service that never answers ends in a message, not a hang',
    () async {
      var sends = 0;
      final service = RememberedPrinting(
        preference: preference,
        info: () async => direct,
        printers: () => Completer<List<Printer>>().future,
        send: (_, _, _, _) async {
          sends++;
          return true;
        },
        discoveryTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        service.print(bytes, 'Sheets', choose: (_) async => a),
        throwsA(isA<TournamentException>()),
      );
      expect(sends, 0);
      expect(service.busy, false, reason: 'Print works again afterwards');
    },
  );
}
