import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/application/diagnostics.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/diagnostic_log.dart';
import '../support.dart';

void main() {
  test(
    'save failure records operation, context and full stack in an exportable file',
    () {
      final dir = Directory.systemTemp.createTempSync('meow-diagnostics-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final log = DiagnosticLog(dir);
      final previous = Diagnostics.sink;
      Diagnostics.sink = log.write;
      addTearDown(() => Diagnostics.sink = previous);
      final c = fixture(count: 4);
      c.dispose();
      expect(
        () => c.change('Import 24 players', c.event!),
        throwsA(isA<TournamentException>()),
      );
      final text = log.read();
      expect(text, contains('ERROR save event — failed'));
      expect(text, contains('  action: Import 24 players'));
      expect(text, contains('  Error: This event has closed.'));
      expect(text, contains('  Stack trace:\n    #0'));
      expect(text, contains('TournamentControllerCore.change'));
      expect(text, matches(RegExp(r'\d{4}-\d{2}-\d{2}T.*Z INFO save event')));
      expect(text, isNot(contains(r'\n')));
    },
  );

  test(
    'rotation retains the previous file; a failed logger cannot block saves',
    () {
      final dir = Directory.systemTemp.createTempSync('meow-diagnostics-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final log = DiagnosticLog(dir, maxBytes: 8);
      log.write('first entry');
      log.write('second entry');
      expect(log.read(), 'first entry\nsecond entry\n');
      log.write('third entry');
      expect(log.read(), 'second entry\nthird entry\n');
      final previous = Diagnostics.sink;
      Diagnostics.sink = (_) => throw const FileSystemException('Disk full');
      addTearDown(() => Diagnostics.sink = previous);
      final c = fixture(count: 4);
      addTearDown(c.dispose);
      c.savePlayer(c.event!.players.first.copy(rating: 1600));
      expect(c.event!.players.first.rating, 1600);
    },
  );

  test('the text log persists across sessions without an export', () {
    final dir = Directory.systemTemp.createTempSync('meow-diagnostics-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final previous = Diagnostics.sink;
    addTearDown(() => Diagnostics.sink = previous);
    Diagnostics.sink = DiagnosticLog(dir).write;
    Diagnostics.record('first session', 'started');
    // A newly opened logger appends to the same file, as on the next launch.
    final reopened = DiagnosticLog(dir);
    Diagnostics.sink = reopened.write;
    Diagnostics.record('second session', 'started');
    final text = File(reopened.file.path).readAsStringSync();
    expect(text, contains('INFO first session — started'));
    expect(text, contains('INFO second session — started'));
  });

  test('logged source URLs omit query credentials and fragments', () {
    expect(
      Diagnostics.sourceUrl(
        'https://user:secret@example.org/entries?token=secret#private',
      ),
      'https://example.org/entries',
    );
  });
}
