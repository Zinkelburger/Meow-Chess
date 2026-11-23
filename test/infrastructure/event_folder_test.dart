import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/event_folder.dart';
import 'package:path/path.dart' as p;

import '../support.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('meow-event-folder-'));
  tearDown(() => dir.deleteSync(recursive: true));

  List<String> listed(String folder) => [
    for (final f in Directory(folder).listSync())
      if (f is File) p.basename(f.path),
  ]..sort();

  test('a new event folder is named as the event, less what disks refuse', () {
    expect(eventFolderName('Tornado #150'), 'Tornado #150');
    expect(eventFolderName('  Spring: Open / U1800?  '), 'Spring Open U1800');
    expect(eventFolderName('Club night...'), 'Club night');
    expect(eventFolderName('CON'), 'CON tournament');
    expect(eventFolderName('???'), 'Tournament');
    expect(eventFolderName('x' * 100), hasLength(80));
  });

  test(
    'a new event folder is made, an empty one reused, a used one refused',
    () {
      final made = createEventFolder(dir.path, 'Tornado #150');
      expect(made.path, p.join(dir.path, 'Tornado #150'));
      expect(made.created, isTrue);
      expect(Directory(made.path).existsSync(), isTrue);
      // An empty folder already there is used, but was not made now.
      final again = createEventFolder(dir.path, 'Tornado #150');
      expect(again.path, made.path);
      expect(again.created, isFalse);
      File(p.join(made.path, 'tornado-150.meow')).writeAsStringSync('');
      expect(
        () => createEventFolder(dir.path, 'Tornado #150'),
        throwsA(
          isA<TournamentException>().having(
            (e) => e.message,
            'message',
            contains('Tornado #150 already exists'),
          ),
        ),
      );
      expect(
        () => createEventFolder(p.join(dir.path, 'gone'), 'Next'),
        throwsA(isA<TournamentException>()),
      );
    },
  );

  test('an event has its own folder only when it is the one .meow there', () {
    final memory = fixture();
    addTearDown(memory.dispose);
    expect(eventFolder(memory.repository), isNull);

    final c = fixture(path: p.join(dir.path, 'event.meow'));
    addTearDown(c.dispose);
    // Alone in a folder this app did not make for it (an older event kept
    // on the Desktop, say): nothing is saved there unasked.
    expect(eventFolder(c.repository), isNull);
    markEventFolder(c.repository, dir.path);
    expect(eventFolder(c.repository), dir.path);
    File(p.join(dir.path, 'other.MEOW')).writeAsStringSync('');
    expect(eventFolder(c.repository), isNull);
  });

  test('a copy of the event saved elsewhere has no folder of its own', () {
    final c = fixture(path: p.join(dir.path, 'event.meow'));
    addTearDown(c.dispose);
    markEventFolder(c.repository, p.join(dir.path, 'elsewhere'));
    expect(eventFolder(c.repository), isNull);
    SwissSysFolderFiles(c.repository).update(c.event!);
    expect(listed(dir.path).where((n) => n.contains('.S')), isEmpty);
  });

  test('reports go into the event folder, or ask where without one', () async {
    final asked = <String>[];
    Future<String?> ask(String name, List<int> bytes) async {
      asked.add(name);
      return null;
    }

    final c = fixture(path: p.join(dir.path, 'event.meow'));
    addTearDown(c.dispose);
    markEventFolder(c.repository, dir.path);
    final path = await saveForEvent(c.repository, 'a.pdf', [1, 2], ask: ask);
    expect(path, p.join(dir.path, 'a.pdf'));
    expect(File(path!).readAsBytesSync(), [1, 2]);
    expect(asked, isEmpty);

    final memory = fixture();
    addTearDown(memory.dispose);
    expect(await saveForEvent(memory.repository, 'b.pdf', [3], ask: ask), null);
    expect(asked, ['b.pdf']);
  });

  test('SwissSys files follow the event round by round', () async {
    final c = fixture(
      count: 8,
      format: Format.swiss,
      path: p.join(dir.path, 'event.meow'),
    );
    addTearDown(c.dispose);
    markEventFolder(c.repository, dir.path);
    final files = SwissSysFolderFiles(c.repository);
    void update() => files.update(c.event!);
    List<String> swissSys() =>
        listed(dir.path).where((n) => n.contains('.S')).toList();

    update();
    expect(swissSys(), ['Quad 1.S0C', 'Quad 2.S0C']);

    c.post(await c.propose());
    update();
    expect(swissSys(), [
      'Quad 1.S0C',
      'Quad 1.S1A',
      'Quad 2.S0C',
      'Quad 2.S1A',
    ]);

    // Each result rewrites the round's file.
    List<List<int>> roundOne() => [
      for (final n in ['Quad 1.S1A', 'Quad 2.S1A'])
        File(p.join(dir.path, n)).readAsBytesSync(),
    ];
    final before = roundOne();
    final games = [for (final s in c.event!.sections) ...s.rounds.last.games];
    c.recordResult(games.first.id, Outcome.draw);
    update();
    expect(roundOne(), isNot(before));

    for (final g in games.skip(1)) {
      c.recordResult(g.id, Outcome.whiteWin);
    }
    update();
    expect(swissSys(), [
      'Quad 1.S0C',
      'Quad 1.S1A',
      'Quad 1.S1C',
      'Quad 2.S0C',
      'Quad 2.S1A',
      'Quad 2.S1C',
    ]);

    c.post(await c.propose());
    update();
    expect(swissSys(), containsAll(['Quad 1.S2A', 'Quad 2.S2A']));

    // Undone pairings leave the folder: a screen never shows them.
    c.undo();
    update();
    expect(swissSys(), [
      'Quad 1.S0C',
      'Quad 1.S1A',
      'Quad 1.S1C',
      'Quad 2.S0C',
      'Quad 2.S1A',
      'Quad 2.S1C',
    ]);
  });

  test('SwissSys files are not written into a folder other events share', () {
    final c = fixture(path: p.join(dir.path, 'event.meow'));
    addTearDown(c.dispose);
    markEventFolder(c.repository, dir.path);
    File(p.join(dir.path, 'other.meow')).writeAsStringSync('');
    SwissSysFolderFiles(c.repository).update(c.event!);
    expect(listed(dir.path).where((n) => n.contains('.S')), isEmpty);
  });

  test(
    'another event\'s SwissSys files in the folder are never written over or '
    'removed',
    () async {
      final c = fixture(
        count: 8,
        format: Format.swiss,
        path: p.join(dir.path, 'club.meow'),
      );
      addTearDown(c.dispose);
      markEventFolder(c.repository, dir.path);
      // Last month's event, saved by SwissSys in the same folder.
      final lastMonth = {
        'Quad 1.S5C': [5],
        'Quad 1.S1A': [1],
      };
      for (final MapEntry(:key, :value) in lastMonth.entries) {
        File(p.join(dir.path, key)).writeAsBytesSync(value);
      }
      final files = SwissSysFolderFiles(c.repository);
      files.update(c.event!);
      c.post(await c.propose());
      files.update(c.event!);
      c.undo();
      files.update(c.event!);
      for (final MapEntry(:key, :value) in lastMonth.entries) {
        expect(
          File(p.join(dir.path, key)).readAsBytesSync(),
          value,
          reason: key,
        );
      }
      // This event's own files still follow it.
      expect(listed(dir.path), containsAll(['Quad 1.S0C', 'Quad 2.S0C']));
      expect(listed(dir.path), isNot(contains('Quad 2.S1A')));
    },
  );

  test(
    'files written before the event was reopened are still its own',
    () async {
      final path = p.join(dir.path, 'event.meow');
      final c = fixture(count: 8, format: Format.swiss, path: path);
      addTearDown(c.dispose);
      markEventFolder(c.repository, dir.path);
      SwissSysFolderFiles(c.repository).update(c.event!);
      c.post(await c.propose());
      SwissSysFolderFiles(c.repository).update(c.event!);
      expect(listed(dir.path), contains('Quad 1.S1A'));
      // A fresh instance, as after reopening, knows the files are this
      // event's: the undone round's file goes.
      c.undo();
      SwissSysFolderFiles(c.repository).update(c.event!);
      expect(listed(dir.path), isNot(contains('Quad 1.S1A')));
      expect(listed(dir.path), contains('Quad 1.S0C'));
    },
  );

  test('files saved by hand into the event folder are kept current', () async {
    final c = fixture(
      count: 8,
      format: Format.swiss,
      path: p.join(dir.path, 'event.meow'),
    );
    addTearDown(c.dispose);
    markEventFolder(c.repository, dir.path);
    c.post(await c.propose());
    // Save SwissSys files, before the folder was kept automatically.
    File(p.join(dir.path, 'Quad 1.S1A')).writeAsBytesSync([0]);
    SwissSysFolderFiles.remember(c.repository, dir.path, ['Quad 1.S1A']);
    SwissSysFolderFiles(c.repository).update(c.event!);
    expect(File(p.join(dir.path, 'Quad 1.S1A')).readAsBytesSync(), isNot([0]));
  });
}
