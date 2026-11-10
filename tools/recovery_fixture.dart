// Synthetic writer for scripts/verify_recovery.py. Never opens an existing event.
//
//   recovery_fixture.dart <new path>               waits for NEXT after each ACK
//   recovery_fixture.dart <new path> --continuous  saves without waiting, so a
//                                                  kill lands mid-save
import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

Future<void> main(List<String> args) async {
  final continuous = args.length == 2 && args[1] == '--continuous';
  if (args.isEmpty ||
      args.length > 2 ||
      (args.length == 2 && !continuous) ||
      File(args.first).existsSync()) {
    throw ArgumentError('Provide a new disposable event path.');
  }
  final repository = SqliteEventRepository(args.first);
  var event = Event(
    id: 'recovery-fixture',
    name: 'Recovery fixture',
    date: '2026-09-28',
    practice: true,
  );
  final commands = StreamIterator(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  // Continuous runs must still be saving when the harness kills them.
  final last = continuous ? 1000000 : 100;
  for (var revision = 1; revision <= last; revision++) {
    event = repository.commit(
      event.copy(
        name: 'Revision $revision',
        players: [
          for (var i = 0; i < 120; i++)
            Player(id: 'entrant-$i', name: 'Player $i revision $revision'),
        ],
      ),
      expectedRevision: revision - 1,
      action: 'Synthetic commit $revision',
    );
    stdout.writeln('ACK ${event.revision} $pid');
    await stdout.flush();
    if (continuous) continue;
    // The harness kills us while waiting here: never close/checkpoint first.
    if (!await commands.moveNext() || commands.current != 'NEXT') break;
  }
  repository.close();
}
