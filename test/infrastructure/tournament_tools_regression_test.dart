import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/tournament_tools.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late TournamentTools tools;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('meow-tools-');
    tools = TournamentTools(directory.path);
  });
  tearDown(() {
    tools.close();
    directory.deleteSync(recursive: true);
  });

  test('a rated event is never turned into a practice copy in place', () async {
    final created = await tools.call('create_event', {
      'path': 'spring.meow',
      'name': 'Spring Open',
      'date': '2026-10-10',
      'practice': false,
    });
    expect(created['practice'], isFalse);
    final revision = tools.event.revision;
    await expectLater(
      tools.call('update_event', {
        'practice': true,
        'expectedRevision': revision,
      }),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('cannot be turned into a practice copy'),
        ),
      ),
    );
    expect(tools.event.practice, isFalse);
    expect(tools.event.revision, revision);
    // Other metadata, and repeating practice: false, still save.
    await tools.call('update_event', {
      'venue': 'Boylston Chess Club',
      'practice': false,
      'expectedRevision': revision,
    });
    expect(tools.event.venue, 'Boylston Chess Club');
  });

  test('a failed create leaves no file behind, so it can be retried', () async {
    final locked = Directory(p.join(directory.path, 'locked'))..createSync();
    Process.runSync('chmod', ['555', locked.path]);
    addTearDown(() => Process.runSync('chmod', ['755', locked.path]));
    try {
      File(p.join(locked.path, 'probe')).createSync();
      markTestSkipped('Folder permissions are not enforced here.');
      return;
    } on FileSystemException {
      // Expected: the folder refuses new files.
    }
    final arguments = {
      'path': 'locked/spring.meow',
      'name': 'Spring Open',
      'date': '2026-10-10',
    };
    await expectLater(
      tools.call('create_event', arguments),
      throwsA(
        isA<TournamentException>().having(
          (e) => e.message,
          'message',
          contains('cannot create a file in this folder'),
        ),
      ),
    );
    expect(locked.listSync(), isEmpty);
    Process.runSync('chmod', ['755', locked.path]);
    await tools.call('create_event', arguments);
    expect(tools.event.name, 'Spring Open');
  }, skip: Platform.isWindows);
}
