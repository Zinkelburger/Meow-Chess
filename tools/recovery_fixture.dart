// Synthetic writer for scripts/verify_recovery.py. Never opens an existing event.
import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1 || File(args.single).existsSync()) {
    throw ArgumentError('Provide a new disposable event path.');
  }
  final repository = SqliteEventRepository(args.single);
  var event = Event(
    id: 'recovery-fixture',
    name: 'Recovery fixture',
    date: '2026-09-28',
    practice: true,
  );
  final commands = StreamIterator(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  for (var revision = 1; revision <= 100; revision++) {
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
    // The harness kills us while waiting here: never close/checkpoint first.
    if (!await commands.moveNext() || commands.current != 'NEXT') break;
  }
  repository.close();
}
