import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/artifact_file.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';
import 'package:meow_chess/infrastructure/artifact_save.dart';

import '../support.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(
    () => directory = Directory.systemTemp.createTempSync('meow-artifact-'),
  );
  tearDown(() => directory.deleteSync(recursive: true));

  test('native report save cannot overwrite the open event', () async {
    final path = p.join(directory.path, 'event.meow');
    final controller = fixture(path: path);
    final id = controller.event!.id;
    const channel = MethodChannel('meow_chess/file_save');
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => path,
    );
    try {
      await expectLater(
        saveArtifact(
          'standings.csv',
          Uint8List.fromList(utf8.encode('report')),
        ),
        throwsA(isA<TournamentException>()),
      );
      expect(controller.repository.load()!.id, id);
    } finally {
      controller.dispose();
      debugDefaultTargetPlatformOverride = null;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    }
    final reopened = SqliteEventRepository(path);
    try {
      expect(reopened.load()!.id, id);
    } finally {
      reopened.close();
    }
  });

  test('renamed SQLite databases and recovery files are protected', () {
    final path = p.join(directory.path, 'renamed.csv');
    final controller = fixture(path: path);
    try {
      final original = File(path).readAsBytesSync();
      expect(
        () => writeArtifact(path, [1, 2]),
        throwsA(isA<TournamentException>()),
      );
      expect(File(path).readAsBytesSync(), original);
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final recovery = '$path$suffix';
        final existed = File(recovery).existsSync();
        final previous = existed ? File(recovery).readAsBytesSync() : null;
        expect(
          () => writeArtifact(recovery, [1]),
          throwsA(isA<TournamentException>()),
        );
        expect(File(recovery).existsSync(), existed);
        if (existed) expect(File(recovery).readAsBytesSync(), previous);
      }
    } finally {
      controller.dispose();
    }
  });

  test('database aliases cannot bypass protection', () {
    final path = p.join(directory.path, 'event.meow');
    final controller = fixture(path: path);
    try {
      final soft = p.join(directory.path, 'symlink.csv');
      Link(soft).createSync(path);
      expect(
        () => writeArtifact(soft, [1]),
        throwsA(isA<TournamentException>()),
      );
      final hard = p.join(directory.path, 'hardlink.csv');
      expect(Process.runSync('ln', [path, hard]).exitCode, 0);
      expect(
        () => writeArtifact(hard, [1]),
        throwsA(isA<TournamentException>()),
      );
      expect(controller.repository.load()!.players, hasLength(8));
    } finally {
      controller.dispose();
    }
  }, skip: Platform.isWindows);

  test(
    'closed databases are protected even without the tournament extension',
    () {
      final path = p.join(directory.path, 'closed.csv');
      fixture(path: path).dispose();
      final before = File(path).readAsBytesSync();
      expect(SqliteEventRepository.ownsPath(path), isFalse);
      expect(
        () => writeArtifact(path, [1]),
        throwsA(isA<TournamentException>()),
      );
      expect(File(path).readAsBytesSync(), before);
    },
  );

  test('ordinary report replacement is complete and staging is removed', () {
    final path = p.join(directory.path, 'standings.csv');
    File(path).writeAsStringSync('previous');
    writeArtifact(path, utf8.encode('complete report'));
    expect(File(path).readAsStringSync(), 'complete report');
    expect(directory.listSync().map((f) => f.path), [path]);
  });

  test('unrecovered sidecars protect a target with a damaged header', () {
    final path = p.join(directory.path, 'damaged.csv');
    File(path).writeAsStringSync('damaged database header');
    File('$path-wal').writeAsStringSync('recovery');
    expect(() => writeArtifact(path, [1]), throwsA(isA<TournamentException>()));
    expect(File(path).readAsStringSync(), 'damaged database header');
    expect(File('$path-wal').readAsStringSync(), 'recovery');
  });
}
