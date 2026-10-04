import 'package:meow_chess/application/tournament_controller.dart';
import 'package:meow_chess/domain/model.dart';
import 'package:meow_chess/infrastructure/sqlite_event_repository.dart';

TournamentController fixture({
  int count = 8,
  Format format = Format.quad,
  bool practice = false,
  String path = ':memory:',
}) {
  final c = TournamentController(SqliteEventRepository(path));
  c.create('Saturday Quads', practice: practice);
  c.importPlayers([
    for (var i = 0; i < count; i++)
      Player(
        id: 'p$i',
        name: 'Player ${i.toString().padLeft(2, '0')}',
        rating: 2000 - i * 50,
        memberId: '${12000000 + i}',
        checkedIn: true,
      ),
  ]);
  c.applyQuads(c.quadPreview(), c.event!.revision);
  if (format != Format.quad) {
    c.change(
      'Use requested test format',
      c.event!.copy(
        sections: [
          for (final section in c.event!.sections) section.copy(format: format),
        ],
      ),
    );
  }
  return c;
}

// Legacy practice-file fixture; practice creation is no longer exposed.
Future<void> markPracticeCopy(String path) async {
  final repository = SqliteEventRepository(path);
  try {
    final event = repository.load()!;
    repository.commit(
      event.copy(practice: true, backupFolder: ''),
      expectedRevision: event.revision,
      action: 'Mark practice copy',
    );
  } finally {
    repository.close();
  }
}
