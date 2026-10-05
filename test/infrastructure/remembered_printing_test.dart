import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
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
      send: (p, data, name) async {
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
        send: (p, _, _) async {
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
      send: (_, _, _) async {
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
        send: (_, _, _) async {
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
      send: (p, _, _) async {
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
      send: (_, _, _) async => throw StateError('should not submit'),
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
          send: (_, _, _) async {
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
}
