import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/event_save.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('meow_chess/artifact_file');
  late Directory targetDirectory, stagingDirectory;
  late String destination;
  late TournamentController source;

  setUp(() {
    targetDirectory = Directory.systemTemp.createTempSync('meow-event-save-');
    stagingDirectory = Directory.systemTemp.createTempSync('meow-event-stage-');
    destination = p.join(targetDirectory.path, 'selected.meow');
    source = TournamentController(SqliteEventRepository(':memory:'))
      ..create('Snapshot to save');
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    source.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    targetDirectory.deleteSync(recursive: true);
    if (stagingDirectory.existsSync()) {
      stagingDirectory.deleteSync(recursive: true);
    }
  });

  for (final replace in [false, true]) {
    test(
      'native event save ${replace ? 'replaces' : 'creates'} a verified snapshot without sibling staging',
      () async {
        if (replace) {
          final prior = TournamentController(SqliteEventRepository(destination))
            ..create('Previous event');
          prior.dispose();
        }
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          if (call.method == 'stagingDirectory') {
            expect(call.arguments, destination);
            return stagingDirectory.path;
          }
          expect(call.method, 'publish');
          final args = Map<String, dynamic>.from(call.arguments);
          final file = File(args['source']!);
          expect(file.parent.path, stagingDirectory.path);
          expect(args['destination'], destination);
          expect(args['replaceExisting'], replace);
          expect(
            targetDirectory.listSync().map((f) => p.basename(f.path)),
            replace ? ['selected.meow'] : isEmpty,
          );
          final snapshot = SqliteEventRepository(file.path);
          expect(snapshot.load()!.name, 'Snapshot to save');
          expect(snapshot.history(), hasLength(1));
          snapshot.close();
          file.renameSync(destination);
          return null;
        });
        await saveSelectedEvent(source.repository, destination);
        final saved = SqliteEventRepository(destination);
        expect(saved.load()!.encode(), source.event!.encode());
        saved.close();
        expect(stagingDirectory.existsSync(), false);
      },
    );
  }

  test(
    'a file appearing during staging never gains replacement approval',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'stagingDirectory') {
          File(destination).writeAsStringSync('created during staging');
          return stagingDirectory.path;
        }
        final args = Map<String, dynamic>.from(call.arguments);
        expect(args['replaceExisting'], false);
        throw PlatformException(code: 'file-exists');
      });
      await expectLater(
        saveSelectedEvent(source.repository, destination),
        throwsA(isA<PlatformException>()),
      );
      expect(File(destination).readAsStringSync(), 'created during staging');
      expect(stagingDirectory.existsSync(), false);
    },
  );

  test('a new target stays exclusive through native coordination', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'stagingDirectory') return stagingDirectory.path;
      final args = Map<String, dynamic>.from(call.arguments);
      expect(args['replaceExisting'], false);
      File(destination).writeAsStringSync('created by another process');
      // Native moveItem must reject this race rather than switching to replace.
      throw PlatformException(code: 'file-exists');
    });
    await expectLater(
      saveSelectedEvent(source.repository, destination),
      throwsA(isA<PlatformException>()),
    );
    expect(File(destination).readAsStringSync(), 'created by another process');
    expect(stagingDirectory.existsSync(), false);
  });

  test(
    'failed native publication retains previous event and cleans staging',
    () async {
      final prior = TournamentController(SqliteEventRepository(destination))
        ..create('Previous event');
      prior.dispose();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'stagingDirectory') return stagingDirectory.path;
        throw PlatformException(code: 'publication-failed');
      });
      await expectLater(
        saveSelectedEvent(source.repository, destination),
        throwsA(isA<PlatformException>()),
      );
      final saved = SqliteEventRepository(destination);
      expect(saved.load()!.name, 'Previous event');
      saved.close();
      expect(stagingDirectory.existsSync(), false);
    },
  );

  test('an event opened during staging is never replaced', () async {
    TournamentController? opened;
    var published = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'stagingDirectory') {
        opened = TournamentController(SqliteEventRepository(destination))
          ..create('Opened during staging');
        return stagingDirectory.path;
      }
      published = true;
      return null;
    });
    try {
      await expectLater(
        saveSelectedEvent(source.repository, destination),
        throwsA(isA<TournamentException>()),
      );
      expect(published, false);
      expect(opened!.event!.name, 'Opened during staging');
      expect(stagingDirectory.existsSync(), false);
    } finally {
      opened?.dispose();
    }
  });

  test(
    'native publication cannot overwrite a database awaiting recovery',
    () async {
      source.repository.backup(destination);
      File('$destination-wal').writeAsBytesSync([1, 2, 3]);
      var published = false;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'stagingDirectory') return stagingDirectory.path;
        published = true;
        return null;
      });
      await expectLater(
        saveSelectedEvent(source.repository, destination),
        throwsA(isA<TournamentException>()),
      );
      expect(published, false);
      expect(File('$destination-wal').readAsBytesSync(), [1, 2, 3]);
      expect(stagingDirectory.existsSync(), false);
    },
  );

  test(
    'SQLite replacement ownership lasts across asynchronous publication',
    () async {
      source.repository.backup(destination);
      final publishing = Completer<void>(), finish = Completer<void>();
      final operation = SqliteEventRepository.replaceBackup(destination, (
        replaceExisting,
      ) async {
        expect(replaceExisting, true);
        publishing.complete();
        await finish.future;
      });
      await publishing.future;
      final other = sqlite3.open(destination);
      try {
        expect(
          () => other.select('SELECT * FROM event'),
          throwsA(isA<SqliteException>()),
        );
      } finally {
        other.close();
        finish.complete();
        await operation;
      }
      final reopened = SqliteEventRepository(destination);
      expect(reopened.load()!.name, source.event!.name);
      reopened.close();
    },
    skip: Platform.isWindows
        ? 'Windows publication relies on exclusive OS sharing instead.'
        : false,
  );
}
